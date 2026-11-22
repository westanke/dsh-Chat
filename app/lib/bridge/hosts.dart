/// 桥配置导入与主机记录（真机反馈 2026-11-04 第 8 项）。
///
/// 线格式对齐 dsh-companion 的 ConnectionShare（DSH1）：
/// `DSH1:` + URL-safe 无填充 Base64(JSON{displayName, endpoints, token?, ...})。
/// 解码宽容（companion ConnectionShare.kt:62-308 口径）：剔空白/零宽字符、
/// 前缀大小写不敏感且可在全文任意位置、双 Base64 字母表、自动补 `=`、
/// 失败一律返回 null 不抛异常。
/// 存储取明文 JSON 数组（现有 dsh.credentials 本就明文，AES-GCM 收益为负
/// 且违背零依赖——companion 的加密保护的是多主机长期凭据库，这里是单键列表）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'endpoint_select.dart';

/// 一条主机记录（导入/配对成功后落库；点击即可直连）。
class DshHost {
  const DshHost({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    this.token,
    required this.lastUsedAt,
    this.endpoints = const [],
    this.preferredEndpoint,
  });

  factory DshHost.fromJson(Map<String, dynamic> j) => DshHost(
    id: (j['id'] ?? '') as String,
    displayName: (j['displayName'] ?? '') as String,
    baseUrl: (j['baseUrl'] ?? '') as String,
    token: j['token'] as String?,
    lastUsedAt: (j['lastUsedAt'] ?? 0) as int,
    endpoints: [
      for (final e in (j['endpoints'] as List? ?? const []))
        if (e is String) e,
    ],
    preferredEndpoint: j['preferredEndpoint'] as String?,
  );

  /// 幂等 id：FNV-1a 摘要 16 hex（同地址重复导入只更新不重复建行）。
  static String stableId(String baseUrl) {
    final digest = sha256Short(baseUrl);
    return digest;
  }

  final String id;
  final String displayName;

  /// 最近一次连通/导入时的首个地址（老单地址码就是它本身）。
  final String baseUrl;
  final String? token;
  final int lastUsedAt;

  /// DSH1 `endpoints` 的全部候选（隧道在前，其后 LAN/虚拟网）；老记录为空。
  final List<String> endpoints;

  /// 上次连接成功的地址（IKX5KQ 第 4 点：下次先试它，失败立刻换）。
  final String? preferredEndpoint;

  /// 连接时该试的地址表：老记录只有 baseUrl，也要能照常连。
  List<String> get candidates {
    final list = <String>[];
    for (final e in [baseUrl, ...endpoints]) {
      final v = e.trim().replaceAll(RegExp(r'/+$'), '');
      if (v.isEmpty || list.contains(v)) continue;
      list.add(v);
    }
    return list;
  }

  DshHost copyWith({
    String? baseUrl,
    String? preferredEndpoint,
    List<String>? endpoints,
    int? lastUsedAt,
    String? token,
  }) => DshHost(
    id: id,
    displayName: displayName,
    baseUrl: baseUrl ?? this.baseUrl,
    token: token ?? this.token,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    endpoints: endpoints ?? this.endpoints,
    preferredEndpoint: preferredEndpoint ?? this.preferredEndpoint,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'baseUrl': baseUrl,
    'token': ?token,
    'lastUsedAt': lastUsedAt,
    'endpoints': endpoints,
    'preferredEndpoint': ?preferredEndpoint,
  };
}

/// FNV-1a 64 位摘要，hex 16 字符。dart:convert 没有 crypto，
/// 不加依赖（宪法 §8）；幂等键只要求「同输入同输出」，FNV 足够——
/// 注意不能用 base64 前缀截断：相似 URL 的 base64 前 16 位完全相同
/// （真机测试踩过：192.168.1.10 与 .11 的 base64 前 16 位一致）。
/// 稳定摘要（FNV-1a 64 位，hex 16 字符）。dart:convert 没有 crypto，
/// 不加依赖（宪法 §8）；幂等键只要求「同输入同输出」，FNV 足够——
/// 注意不能用 base64 前缀截断：相似 URL 的 base64 前 16 位完全相同
/// （真机测试踩过：192.168.1.10 与 .11 的 base64 前 16 位一致）。
String sha256Short(String input) {
  var hash = 0xcbf29ce484222325;
  for (final unit in utf8.encode(input)) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// 主机记录库：shared_preferences 单键 `dsh.hosts` JSON 数组。
class DshHosts {
  DshHosts._();

  static const String _key = 'dsh.hosts';
  static List<DshHost>? _cache;

  static Future<List<DshHost>> load() async {
    if (_cache != null) return _cache!;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.isEmpty) {
        _cache = const [];
        return _cache!;
      }
      final list = jsonDecode(raw) as List;
      _cache = list
          .whereType<Map>()
          .map((e) => DshHost.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on Object {
      _cache = const [];
    }
    return _cache!;
  }

  /// 按 baseUrl 幂等 upsert（同地址更新 token/名称/时间，不重复建行），
  /// 按 lastUsedAt 降序。
  static Future<void> upsert(DshHost host) async {
    final hosts = [...await load()];
    // 同一条主机可能经不同地址连过（LAN/隧道）：id 相同也算同一条，
    // 否则换个地址连一次就多出一行历史主机（IKX5KQ）。
    final idx = hosts.indexWhere(
      (h) => h.id == host.id && host.id.isNotEmpty || h.baseUrl == host.baseUrl,
    );
    if (idx >= 0) {
      hosts[idx] = host;
    } else {
      hosts.add(host);
    }
    hosts.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    _cache = hosts;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode(hosts.map((h) => h.toJson()).toList()),
    );
  }

  /// 删除单条主机记录（连接页「移除过期/失效记录」）。
  /// 按 baseUrl 优先、id 兜底匹配（兼容早期 id 缺失的历史数据）。
  /// 返回是否命中；缓存与 shared_preferences 同步更新，删空写 `[]`。
  static Future<bool> remove(DshHost host) async {
    final hosts = [...await load()];
    final before = hosts.length;
    hosts.removeWhere((h) =>
        h.baseUrl == host.baseUrl ||
        (host.id.isNotEmpty && h.id == host.id));
    if (hosts.length == before) return false;
    _cache = hosts;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode(hosts.map((h) => h.toJson()).toList()),
    );
    return true;
  }

  static Future<void> clear() async {
    _cache = const [];
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}

/// DSH1 配置文本解码（宽容版，companion ConnectionShare.decode 口径）。
/// 失败返回 null（绝不抛异常）。
DshHost? decodeDsh1(String text) {
  try {
    // 1) 定位前缀（大小写不敏感，可在全文任意位置）；无前缀则整段当 base64 试。
    var payload = text;
    final lower = text.toLowerCase().replaceAll(RegExp(r'\s'), '');
    final idx = lower.indexOf('dsh1:');
    if (idx >= 0) {
      payload = text.replaceAll(RegExp(r'\s'), '').substring(idx + 5);
    } else {
      payload = text.replaceAll(RegExp(r'\s'), '');
    }
    if (payload.isEmpty) return null;
    // 2) 剔除 Base64 字母表外字符（结尾粘上的标点/引号）。
    payload = payload.replaceAll(RegExp(r'[^A-Za-z0-9_\-=]'), '');
    // 3) URL-safe → 标准 + 补 `=`；dart 的 base64Url.decode 遇缺填充会抛。
    var std = payload.replaceAll('_', '/').replaceAll('-', '+');
    final mod = std.length % 4;
    if (mod == 1) return null;
    if (mod != 0) std += '=' * (4 - mod);
    final json = utf8.decode(base64.decode(std), allowMalformed: false);
    // 4) 整段解析；失败截最外层 `{...}` 再试。
    dynamic parsed;
    try {
      parsed = jsonDecode(json);
    } on FormatException {
      final start = json.indexOf('{');
      final end = json.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      parsed = jsonDecode(json.substring(start, end + 1));
    }
    if (parsed is! Map) return null;
    // 5) 提字段：endpoints 全留（IKX5KQ——隧道在首个，其后 LAN/虚拟网；
    // 只取首个会让「在家生成的码出门连不上」/「出门的码回家绕远」）。
    final endpoints = <String>[];
    final rawEndpoints = parsed['endpoints'];
    if (rawEndpoints is List) {
      for (final e in rawEndpoints) {
        if (e is! Map) continue;
        final u = e['baseUrl'];
        if (u is! String || u.trim().isEmpty) continue;
        endpoints.add(u.trim().replaceFirst(RegExp(r'/api/v1/?$'), ''));
      }
    }
    // 兼容极老的码：顶层 baseUrl。
    final topLevel = parsed['baseUrl'];
    if (topLevel is String && topLevel.trim().isNotEmpty) {
      endpoints.add(topLevel.trim().replaceFirst(RegExp(r'/api/v1/?$'), ''));
    }
    final candidates = normalizeEndpoints(endpoints);
    if (candidates.isEmpty) return null;
    final baseUrl = candidates.first;
    final displayName =
        (parsed['displayName'] as String?)?.trim() ?? '导入的主机';
    final token = parsed['token'] as String?;
    return DshHost(
      id: DshHost.stableId(baseUrl),
      displayName: displayName,
      baseUrl: baseUrl,
      token: (token == null || token.isEmpty) ? null : token,
      lastUsedAt: DateTime.now().millisecondsSinceEpoch,
      endpoints: candidates,
      preferredEndpoint: baseUrl,
    );
  } on Object {
    return null;
  }
}
