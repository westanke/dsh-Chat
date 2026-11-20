/// 会话**内容**搜索（内核端点 `session/search`，走 `dshrb-v1` 通用调用面）。
///
/// ## 为什么不是本地过滤
///
/// 抽屉原先是「按标题 `contains` 本地过滤」，只能搜到自己已经拉下来的那批会话标题。
/// 用户输入「审批卡片」这类只出现在正文里的词时它永远搜不到，却表现得像搜过了
/// （空列表）。`session/search` 是内核的真搜索（`{query}` → `{items:[{sessionId,
/// snippet}],hasMore}`，limit 20、snippet ≤240 code point），桥已在白名单里放行。
///
/// ## 三件套：入口 + 空态 + 降级
///
/// 接入一个新能力要能说清「什么条件下走不到」：
/// - **入口**：抽屉搜索框，输入即搜（300ms 防抖，避免每敲一个字打一次内核）；
/// - **降级**：老桥没有 `dshrb-v1` ⇒ 目录为空 ⇒ [supported] 为 false ⇒ 调用方
///   原样退回本地标题过滤，界面不出现「搜索失败」，用户感觉不到能力缺失；
/// - **空态**：三种结局要分开 —— 「没搜到」（真的没有）、「搜不了」（部署侧
///   `session-query` 索引没开，见下）、「还在搜」。
///
/// > **部署侧已知限制**：内核的会话索引在本机默认配置里是 `openAt "never"`
/// > （桥 `docs/project/CHANGELOG-DEV.md` 有记）。那种部署上端点调得通、结果却是空的
/// > ——所以「空结果」不能当成「索引可用但没命中」来承诺，文案上别写死「没有匹配」。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/dlog.dart';
import '../bridge/gateway.dart';

/// 内核端点名（白名单里那条，`kernel-endpoints` 目录用它做键）。
const String kSessionSearchEndpoint = 'session/search';

/// 一条内容命中：会话 id + 摘要片段。片段里**可能**带高亮标记，本仓按纯文本渲染。
class SessionSearchHit {
  const SessionSearchHit({required this.sessionId, required this.snippet});

  final String sessionId;

  /// 命中处的片段（内核已压到 ≤240 code point）。可能为空——那样就只显示会话标题。
  final String snippet;

  @override
  String toString() => 'SessionSearchHit($sessionId)';
}

/// 解析 `session/search` 的返回值 `{items:[{sessionId, snippet}], hasMore}`。
///
/// 宽容到底：形状不认识就回空表，不抛错——搜索失败不该让抽屉红一片。
List<SessionSearchHit> parseSessionSearchHits(Object? value) {
  if (value is! Map) return const [];
  final items = value['items'];
  if (items is! List) return const [];
  final out = <SessionSearchHit>[];
  for (final item in items) {
    if (item is! Map) continue;
    final id = item['sessionId'];
    if (id is! String || id.isEmpty) continue;
    final snippet = item['snippet'];
    out.add(
      SessionSearchHit(
        sessionId: id,
        snippet: snippet is String ? _tidySnippet(snippet) : '',
      ),
    );
  }
  return out;
}

/// 片段里的换行会被压成空格：抽屉里一行装不下多行，留着只会被 ellipsis 截掉。
String _tidySnippet(String raw) {
  final oneLine = raw.replaceAll(RegExp(r'[\r\n\t ]+'), ' ').trim();
  return oneLine;
}

/// 拼 `session/search` 的 `args`。
///
/// **键名以目录为准**：`kernel-endpoints` 每条都带 `wires`（该端点接受的 wire 键），
/// 内核 strict codec 既拒缺键也拒多键，所以不硬编码键名——目录说叫什么就叫什么。
/// 当前内核那条是单个必填 `request`（`{request: {query}}`），但桥换版本、描述符
/// 改名时这里跟着目录走，不会静默失配。
///
/// 目录里没有这个端点（此时本来就 `supported == false`）时退回已知形状，让调用链
/// 至少能拿到一个明确的错误帧而不是空参数。
Map<String, dynamic> sessionSearchArgs(KernelEndpoint? endpoint, String query) {
  final wires = endpoint?.wires ?? const ['request'];
  final request = {'query': query};
  if (wires.contains('request')) return {'request': request};
  if (wires.contains('query')) return {'query': query};
  // 描述符形状不认识：把 query 塞进第一个 wire 键，让桥按它自己的判据拒绝并回
  // 明确的参数错误（而不是本仓猜一个形状、报出一个更难查的错）。
  if (wires.isNotEmpty) return {wires.first: request};
  return {'request': request};
}

/// 内容搜索的编排：防抖、并发序、三种结局。
///
/// 抽屉只负责「把输入喂进来、把结果画出去」，其余都在这里——这样搜索的状态机
/// 不散在 UI 里，也能被单测直接驱动。
class SessionSearchController extends ChangeNotifier {
  SessionSearchController({required this.gateway, this.debounce = const Duration(milliseconds: 300)}) {
    // 端点目录是 hello 之后**异步**到达的（重连时还会先清空）。监听它，才能在
    // 「能力刚可用」的那一刻把用户已经输好的查询补发出去；只听 drawer 自身的
    // setState 会漏掉这个时刻（真机踩过：输完字这一节整节不出现）。
    _catalog = gateway.kernelCatalogListenable;
    _catalogWasSupported = supported;
    _catalog.addListener(_onCatalogChanged);
  }

  final GatewayClient gateway;

  late final ValueListenable<List<KernelEndpoint>> _catalog;
  bool _catalogWasSupported = false;

  /// 目录变了：能力从「不可用」变「可用」时把已有的查询补发出去。
  void _onCatalogChanged() {
    final now = supported;
    if (now == _catalogWasSupported) return;
    _catalogWasSupported = now;
    if (!now) {
      // 能力消失（重连把目录清空了）：撤掉命中，别让用户点进一个已经不存在的入口。
      _timer?.cancel();
      _seq++;
      _hits = const [];
      _busy = false;
      _error = null;
      notifyListeners();
      return;
    }
    if (_query.isEmpty) {
      notifyListeners();
      return;
    }
    // 查询先到、能力后到：补发。
    _busy = true;
    _error = null;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_run(_query)));
  }

  /// 输入停顿多久才真发请求。连打五个字只打一次内核。
  final Duration debounce;

  Timer? _timer;

  /// 请求序号：只认最后一次发出的那批结果（先发后到的旧结果必须丢掉，
  /// 否则快速改词时列表会闪回上一次的命中）。
  int _seq = 0;

  String _query = '';
  List<SessionSearchHit> _hits = const [];
  bool _busy = false;
  String? _error;

  /// 当前查询串（已 trim）。
  String get query => _query;

  /// 内容命中（按内核给的顺序，未去重——同一会话可能命中多处）。
  List<SessionSearchHit> get hits => _hits;

  /// 正在搜。
  bool get busy => _busy;

  /// 失败原因（网络/超时/端点报错）；null = 没失败。**空结果不算失败**。
  String? get error => _error;

  /// 这次连接到底能不能做内容搜索。
  ///
  /// 判的是「能力位 + 目录里有这个端点」：老桥没协商 `dshrb-v1` ⇒ 目录为空；
  /// 新版桥但内核没装这个端点 ⇒ 目录里没有它。两种情况调用方都该退回本地过滤。
  bool get supported =>
      gateway.kernelCallsEnabled &&
      gateway.kernelEndpoint(kSessionSearchEndpoint) != null;

  /// 是否有话要说。
  ///
  /// 判据是「**有没有查询串**」，不是「有没有命中」——空结果恰恰是最需要说出口的
  /// 结局（真机 v1.0.21 第一次联调就踩了：写成有命中才可见时，搜不到东西整节
  /// 直接消失，看起来像搜索没生效，而不是「没有匹配」）。
  bool get visible => _query.isNotEmpty;

  /// 输入变化。查询串没变（比如只是光标移动）就什么都不做。
  void update(String raw) {
    final next = raw.trim();
    if (next == _query) return;
    _query = next;
    _timer?.cancel();
    if (next.isEmpty) {
      // 清空 = 立刻回到未搜索态，别让旧命中和旧错误赖在列表上。
      _seq++;
      _hits = const [];
      _busy = false;
      _error = null;
      notifyListeners();
      return;
    }
    if (!supported) {
      // 能力还没到（目录异步到）——**留住查询串**，等 _onCatalogChanged 补发。
      _hits = const [];
      _busy = false;
      _error = null;
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    _timer = Timer(debounce, () => unawaited(_run(next)));
  }

  /// 清空（抽屉关闭/会话切换时调用）。
  void clear() {
    _timer?.cancel();
    _seq++;
    if (_query.isEmpty && _hits.isEmpty && !_busy && _error == null) return;
    _query = '';
    _hits = const [];
    _busy = false;
    _error = null;
    notifyListeners();
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    final result = await gateway.kernelCall(
      kSessionSearchEndpoint,
      args: sessionSearchArgs(gateway.kernelEndpoint(kSessionSearchEndpoint), q),
    );
    DshLog.w(
      '[search] q="$q" ok=${result.ok} '
      'code=${result.code} hits=${result.ok ? parseSessionSearchHits(result.value).length : -1}',
    );
    if (seq != _seq) return; // 已有更新的查询发出，这批结果作废
    _busy = false;
    if (result.ok) {
      _hits = parseSessionSearchHits(result.value);
      _error = null;
    } else {
      _hits = const [];
      _error = result.message ?? result.code ?? '搜索失败';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalogChanged);
    _timer?.cancel();
    super.dispose();
  }
}
