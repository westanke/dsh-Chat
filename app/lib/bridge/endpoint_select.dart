/// DSH1 候选地址探活择优（IKX5KQ）。
///
/// 桥把 `DSH1:` 里的 `endpoints` 从一条改成**有序候选列表**（隧道在前，其后是
/// 局域网/虚拟网地址）。客户端不能只取首个：一份码要「在家走 LAN、在外走隧道」，
/// 就得把所有候选都留着，连接时并发探活、择优，失败再换下一条。
///
/// 择优顺序（用户 2026-11-23 定的口径）：**局域网 → 虚拟网 → 隧道 → 其它**，
/// 同一档里按延迟取最快，并列时上次成功过的地址优先。
/// 这样在家一定走局域网（哪怕比隧道慢几十毫秒），在外才落到隧道；
/// 虚拟网（100.64/10 CGNAT，Tailscale 之类）排在隧道前面，因为它通常更直连。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 地址类型，同时也是择优的档位（值越小越优先）：
/// `lan` 局域网 → `virtualNet` 虚拟网（100.64/10）→ `tunnel` 隧道 → `other` 公网。
enum EndpointKind { lan, virtualNet, tunnel, other }

/// 探活超时（单条）：桥的 healthz 是纯内存应答，2.5s 足够；
/// 再长会让「两条都不通」的等待变得难以忍受。
const Duration kEndpointProbeTimeout = Duration(milliseconds: 2500);

EndpointKind classifyEndpoint(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  if (host.contains('trycloudflare.com') ||
      host.contains('ngrok') ||
      host.contains('tunnel')) {
    return EndpointKind.tunnel;
  }
  if (isVirtualNetHost(host)) return EndpointKind.virtualNet;
  if (isPrivateHost(host)) return EndpointKind.lan;
  return EndpointKind.other;
}

/// 虚拟网地址：100.64/10（CGNAT，Tailscale/ZeroTier 常用）。
/// 单独成档：它比隧道直连，但比真局域网绕，排在两者中间。
bool isVirtualNetHost(String host) {
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.').firstMatch(host.toLowerCase());
  if (v4 == null) return false;
  return int.parse(v4.group(1)!) == 100 &&
      int.parse(v4.group(2)!) >= 64 &&
      int.parse(v4.group(2)!) <= 127;
}

/// 去掉 IPv6 方括号与 zone id，供分类使用。
/// `Uri.host` 对 IPv6 返回不带方括号的文本，但调用方/旧测试也可能传 `[fd00::1]`。
String _bareHost(String host) {
  var h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) {
    h = h.substring(1, h.length - 1);
  }
  final zone = h.indexOf('%');
  return zone == -1 ? h : h.substring(0, zone);
}

bool _isPrivateIPv6(String host) {
  final h = _bareHost(host);
  if (h == '::1' || h == '0:0:0:0:0:0:0:1') return true;
  // IPv4-mapped：`::ffff:192.168.1.5`，也接受十六进制写法。
  if (h.startsWith('::ffff:')) {
    final tail = h.substring('::ffff:'.length);
    if (tail.contains('.')) return isPrivateHost(tail);
    final parts = tail.split(':');
    if (parts.length == 2 &&
        parts.every((p) => RegExp(r'^[0-9a-f]{1,4}$').hasMatch(p))) {
      final high = int.parse(parts[0], radix: 16);
      final low = int.parse(parts[1], radix: 16);
      return isPrivateHost('${high >> 8}.${high & 0xff}.${low >> 8}.${low & 0xff}');
    }
    return false;
  }
  // 首段判断 fc00::/7（ULA）与 fe80::/10（link-local）。
  final firstText = h.split(':').first;
  final first = firstText.isEmpty ? 0 : int.tryParse(firstText, radix: 16);
  if (first == null) return false;
  if (first >= 0xfc00 && first <= 0xfdff) return true;
  if (first >= 0xfe80 && first <= 0xfebf) return true;
  return false;
}

/// 私有/虚拟网地址：10/8、172.16/12、192.168/16、100.64/10（CGNAT，
/// 移动/校园网常见）、回环、`.local` 与 IPv6 ULA/link-local/loopback。
/// IPv6 全球单播（2000::/3）算公网，交给隧道/直连探活而不是 LAN 优先。
bool isPrivateHost(String host) {
  if (host.isEmpty) return false;
  final h = _bareHost(host);
  if (h.isEmpty) return false;
  if (h == 'localhost' || h.endsWith('.local')) return true;
  if (h.contains(':')) return _isPrivateIPv6(h);
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (v4 != null) {
    final a = int.parse(v4.group(1)!);
    final b = int.parse(v4.group(2)!);
    if (a == 127 || a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 100 && b >= 64 && b <= 127) return true; // 100.64/10
    return false;
  }
  return false;
}

/// 单条地址的探活结果。
class EndpointProbe {
  const EndpointProbe({
    required this.baseUrl,
    required this.ok,
    this.latencyMs,
    this.error,
  });

  final String baseUrl;
  final bool ok;
  final int? latencyMs;
  final String? error;

  EndpointKind get kind => classifyEndpoint(baseUrl);

  /// 「192.168.1.5:3090 42ms」「…trycloudflare.com 超时」这类诊断短句。
  String get label {
    final shown = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    if (ok) return '$shown ${latencyMs ?? '?'}ms';
    return '$shown ${error ?? '不可达'}';
  }
}

/// 探活一条地址：`GET /api/v1/healthz`（bridge 免鉴权端点）。
/// 返回 HTTP 状态即算可达（4xx 也证明路通了，鉴权/版本问题由握手报）。
Future<EndpointProbe> probeEndpoint(
  String baseUrl, {
  Duration timeout = kEndpointProbeTimeout,
  HttpClient? client,
}) async {
  final own = client == null;
  final http = client ?? HttpClient();
  // 候选地址（LAN/隧道）必须直连：系统代理会把 127.0.0.1/192.168.x 也
  // 转给代理，探活结果就成了「代理通 = 地址通」的假阳性。
  http.findProxy = (uri) => 'DIRECT';
  http.connectionTimeout = timeout;
  final sw = Stopwatch()..start();
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  try {
    final req = await http
        .getUrl(Uri.parse('$base/api/v1/healthz'))
        .timeout(timeout);
    final res = await req.close().timeout(timeout);
    await res.drain<void>().timeout(timeout);
    sw.stop();
    final status = res.statusCode;
    if (status >= 500) {
      return EndpointProbe(
        baseUrl: baseUrl,
        ok: false,
        latencyMs: sw.elapsedMilliseconds,
        error: 'HTTP $status',
      );
    }
    return EndpointProbe(
      baseUrl: baseUrl,
      ok: true,
      latencyMs: sw.elapsedMilliseconds,
    );
  } on TimeoutException {
    return EndpointProbe(baseUrl: baseUrl, ok: false, error: '探活超时');
  } on SocketException catch (e) {
    return EndpointProbe(
      baseUrl: baseUrl,
      ok: false,
      error: e.osError?.message ?? '连不上',
    );
  } on Object catch (e) {
    return EndpointProbe(baseUrl: baseUrl, ok: false, error: _short(e));
  } finally {
    if (own) http.close(force: true);
  }
}

String _short(Object e) {
  final s = e.toString();
  return s.length <= 60 ? s : '${s.substring(0, 60)}…';
}

/// 并发探活（总耗时≈最慢那条），空表返回空表。
Future<List<EndpointProbe>> probeEndpoints(
  List<String> baseUrls, {
  Duration timeout = kEndpointProbeTimeout,
  HttpClient? client,
}) async {
  if (baseUrls.isEmpty) return const [];
  final own = client == null;
  final http = client ?? HttpClient();
  try {
    // 并发探活：总耗时≈最慢那条；共用连接池，结束才关。
    return await Future.wait(
      baseUrls.map((u) => probeEndpoint(u, timeout: timeout, client: http)),
    );
  } finally {
    if (own) http.close(force: true);
  }
}

/// 在可达的候选里择优：先按档位（局域网 → 虚拟网 → 隧道 → 其它），
/// 同档按延迟，并列时上次成功过的地址优先。全不可达返回 null。
String? pickEndpoint(List<EndpointProbe> probes, {String? preferred}) {
  final ok = probes.where((p) => p.ok).toList();
  if (ok.isEmpty) return null;
  ok.sort((a, b) {
    final r = a.kind.index.compareTo(b.kind.index);
    if (r != 0) return r;
    final l = (a.latencyMs ?? 1 << 30).compareTo(b.latencyMs ?? 1 << 30);
    if (l != 0) return l;
    if (preferred != null) {
      if (a.baseUrl == preferred) return -1;
      if (b.baseUrl == preferred) return 1;
    }
    return 0;
  });
  return ok.first.baseUrl;
}

/// 探活 + 择优的结果（连接页诊断面板直接读 [note]）。
class EndpointSelection {
  const EndpointSelection({required this.probes, required this.chosen});

  final List<EndpointProbe> probes;
  final String? chosen;

  bool get allFailed => chosen == null;

  /// 一句人话：「试了 2 条：LAN 42ms ✓、隧道 380ms ✓ → 选 LAN」；
  /// 全失败时逐条给原因（现在只有一条地址时也照旧能看）。
  String get note {
    if (probes.isEmpty) return '';
    final tried = probes.map((p) => p.label).join('、');
    if (chosen == null) return '试了 ${probes.length} 条都不通：$tried';
    final picked = probes.firstWhere((p) => p.baseUrl == chosen);
    final why = switch (picked.kind) {
      EndpointKind.lan => '局域网优先',
      EndpointKind.virtualNet => '虚拟网优先',
      EndpointKind.tunnel => '隧道（同档按延迟）',
      EndpointKind.other => '公网（同档按延迟）',
    };
    return '试了 ${probes.length} 条：$tried → 选 ${_shorten(chosen!)}（$why）';
  }

  static String _shorten(String url) =>
      url.replaceFirst(RegExp(r'^https?://'), '');
}

/// 连接前跑一次：并发探活全部候选，择优返回；全失败也把每条原因带回去。
Future<EndpointSelection> selectEndpoint(
  List<String> baseUrls, {
  String? preferred,
  Duration timeout = kEndpointProbeTimeout,
  HttpClient? client,
}) async {
  final probes = await probeEndpoints(baseUrls, timeout: timeout, client: client);
  // probeEndpoints 的关闭是 concurrent 的，但 Future.wait 之后才关；
  // 这里 probeEndpoints 内部已 close，无需再管。
  final chosen = pickEndpoint(probes, preferred: preferred);
  return EndpointSelection(probes: probes, chosen: chosen);
}

/// 把探活结果序列化成一行诊断（设置页/日志用）。
String describeProbes(List<EndpointProbe> probes) =>
    probes.map((p) => '${p.baseUrl}=${p.ok ? '${p.latencyMs}ms' : p.error}').join('; ');

/// 便于测试：把候选表去重（保序，去掉空串与尾部斜杠）。
List<String> normalizeEndpoints(Iterable<String> raw) {
  final out = <String>[];
  for (final e in raw) {
    final v = e.trim().replaceAll(RegExp(r'/+$'), '');
    if (v.isEmpty || out.contains(v)) continue;
    out.add(v);
  }
  return out;
}

/// 探活结果的 JSON 摘要（落日志/诊断，不参与业务）。
String probesToJson(List<EndpointProbe> probes) => jsonEncode([
  for (final p in probes)
    {'url': p.baseUrl, 'ok': p.ok, 'ms': p.latencyMs, 'error': p.error},
]);
