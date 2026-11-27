/// 历史加载的健壮性回归（2026-11-27 真机三连反馈）：
/// 1) `did not answer ... within 10000ms` 后应自动重试而不是只刷红条；
/// 2) 最后一页全是工具/过程事件时，应继续向前取到「人话」正文；
/// 3) 打开看过的会话时，先用快照上屏，网络刷新在后台跑（stale-while-revalidate）。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/ui/chat_history_actions.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/history_snapshot_cache.dart';

Map<String, dynamic> _event(String type, int seq, Map<String, dynamic> data) =>
    {'type': type, 'seq': seq, 'data': data};

Map<String, dynamic> _user(int seq, String text) => _event(
  'user/message',
  seq,
  {'content': text, 'source': {'kind': 'user'}},
);

/// assistant 正文；[text] 为空白时装配出来是「无正文」的过程行（人类读不到）。
Map<String, dynamic> _assistant(int seq, String text) => _event(
  'assistant/message',
  seq,
  {
    'content': [if (text.isNotEmpty) {'type': 'text', 'text': text}],
  },
);

/// 工具调用过程行：装配成 role=process（默认折叠，人类读不到正文）。
Map<String, dynamic> _process(int seq) => _event(
  'assistant/message',
  seq,
  {
    'content': [
      {'type': 'tool-call', 'id': 'c$seq', 'name': 'bash', 'arguments': '{}'},
    ],
  },
);

Map<String, dynamic> _page(
  List<Map<String, dynamic>> events, {
  bool hasMore = false,
  bool truncated = false,
}) => {'events': events, 'hasMore': hasMore, 'truncated': truncated};

/// 只接管 `history` 帧（扩展方法最终走 requestWithTimeout，子类覆写它才有效）。
class _HistoryGateway extends GatewayClient {
  _HistoryGateway({this.onHistory}) : super(baseUrl: 'http://127.0.0.1:1');

  final Future<Map<String, dynamic>> Function(
    int call,
    Map<String, dynamic> payload,
  )?
  onHistory;
  final List<int?> beforeSeqs = [];
  int calls = 0;

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) {
    if (type != 'history') return Future.value(const {});
    final n = calls++;
    beforeSeqs.add(payload['beforeSeq'] as int?);
    return onHistory?.call(n, payload) ??
        Future.value(_page(const [], hasMore: false));
  }

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async => const {};

  @override
  void subscribe(String? sessionId) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => HistorySnapshotCache.instance.clear());

  test('TIMEOUT 自动重试一次后成功，不写红条', () async {
    final gw = _HistoryGateway(
      onHistory: (call, _) async {
        if (call == 0) {
          throw RequestException('TIMEOUT', 'The host did not answer history.',
              retryable: true);
        }
        return _page([_user(1, '你好')]);
      },
    );
    final state = ChatState(gw)..sessionId = 's1';
    await reloadChatHistory(state);

    expect(gw.calls, 2);
    expect(state.messages.map((m) => m.text), ['你好']);
    expect(state.lastError, isNull);
  });

  test('最后一页没有正文时继续向前取，直到出现人话', () async {
    final gw = _HistoryGateway(
      onHistory: (call, _) async {
        if (call == 0) {
          // 只有无正文的 assistant 过程行：页面上看不到要读的东西。
          return _page([_process(10), _process(11)], hasMore: true);
        }
        return _page([_user(8, '这是人话'), _assistant(9, '回复正文')]);
      },
    );
    final state = ChatState(gw)..sessionId = 's1';
    await reloadChatHistory(state);

    expect(gw.calls, 2);
    // 两条工具调用收口成同一个过程组，组的 seq 取最后一帧（11）。
    expect(gw.beforeSeqs, [null, 11]);
    expect(state.messages.map((m) => m.seq), [8, 9, 11]);
    final human = state.messages.where((m) => m.role != 'process');
    expect(human.map((m) => m.text), ['这是人话', '回复正文']);
  });

  test('打开看过的会话先铺快照再刷新', () async {
    HistorySnapshotCache.instance.put(
      's1',
      HistorySnapshot(
        messages: [ChatMessage(role: 'user', text: '缓存的最后一句', seq: 1)],
        rawEvents: const [],
        hasMore: true,
        truncated: false,
        projections: const {'team': 'x'},
        capturedAt: DateTime.now(),
      ),
    );
    final gate = Completer<Map<String, dynamic>>();
    final gw = _HistoryGateway(onHistory: (_, _) => gate.future);
    final state = ChatState(gw);

    final opening = state.openSession(
      const DshSession(
        id: 's1',
        rootId: 'root',
        updatedAt: 0,
        running: false,
        blank: false,
      ),
    );
    // 网络还没回来时，快照已经上屏、也不再显示整页 loading。
    await Future<void>.delayed(Duration.zero);
    expect(state.messages.map((m) => m.text), ['缓存的最后一句']);
    expect(state.loadingHistory, isFalse);
    expect(state.historyHasMore, isTrue);
    expect(state.projections, {'team': 'x'});

    gate.complete(_page([_user(1, '缓存的最后一句'), _user(2, '新的一句')]));
    await opening;
    expect(state.messages.map((m) => m.text), ['缓存的最后一句', '新的一句']);
  });

  test('刷新成功后把最后一屏写进快照供下次打开', () async {
    final gw = _HistoryGateway(
      onHistory: (_, _) async =>
          _page([_user(3, '存起来')], hasMore: true),
    );
    final state = ChatState(gw)..sessionId = 's1';
    await reloadChatHistory(state);

    final snap = HistorySnapshotCache.instance.take('s1');
    expect(snap, isNotNull);
    expect(snap!.messages.map((m) => m.text), ['存起来']);
    expect(snap.hasMore, isTrue);
  });

  test('翻页也走重试与过程页回填', () async {
    final gw = _HistoryGateway(
      onHistory: (call, payload) async {
        if (call == 0) {
          throw RequestException('TIMEOUT', 'x', retryable: true);
        }
        final before = payload['beforeSeq'] as int?;
        if (before == null) return _page([_user(5, '最新一句')], hasMore: true);
        if (before == 5) return _page([_process(3)], hasMore: true);
        expect(before, 3);
        return _page([_user(1, '更早的人话')]);
      },
    );
    final state = ChatState(gw)..sessionId = 's1';
    await reloadChatHistory(state);
    await loadOlderMessages(state);

    expect(gw.calls, 4);
    expect(gw.beforeSeqs, [null, null, 5, 3]);
    final human = state.messages.where((m) => m.role != 'process');
    expect(human.map((m) => m.text), ['更早的人话', '最新一句']);
  });
}
