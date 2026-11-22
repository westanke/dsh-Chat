/// DSH1 候选地址探活择优（IKX5KQ）。
///
/// 桥把 `DSH1:` 里的 `endpoints` 从一条改成**有序候选列表**（隧道在前，其后是
/// 局域网/虚拟网地址）。客户端不能只取首个：一份码要「在家走 LAN、在外走隧道」，
/// 就得把所有候选都留着，连接时并发探活、择优，失败再换下一条。
///
/// 判据与 companion 的 `EndpointSelection.rank` 对齐：
/// LAN 地址延迟 ≤ 最快地址 ×1.5 的排在最前，其余按延迟，并列看上次成功的地址。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 地址类型：局域网/虚拟网（LAN 优先）、隧道、其它。
enum EndpointKind { lan, tunnel, other }

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
  if (isPrivateHost(host)) return EndpointKind.lan;
  return EndpointKind.other;
}

/// 私有/虚拟网地址：10/8、172.16/12、192.168/16、100.64/10（CGNAT，
/// 移动/校园网常见）、回环、`.local` 与 IPv6 ULA/link-local。
bool isPrivateHost(String host) {
  if (host.isEmpty) return false;
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local')) return true;
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
  if (h.startsWith('[')) {
    final v6 = h.substring(1, h.length - 1);
    return v6 == '::1' ||
        v6.startsWith('fc') ||
        v6.startsWith('fd') ||
        v6.startsWith('fe80');
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

/// 在可达的候选里择优：LAN（延迟 ≤ 最快×1.5）优先，其次按延迟，
/// 并列时上次成功过的地址优先。全不可达返回 null。
String? pickEndpoint(List<EndpointProbe> probes, {String? preferred}) {
  final ok = probes.where((p) => p.ok).toList();
  if (ok.isEmpty) return null;
  final fastest = ok
      .map((p) => p.latencyMs ?? 1 << 30)
      .reduce((a, b) => a < b ? a : b);
  final lanCutoff = (fastest * 1.5).round();
  int rank(EndpointProbe p) => (p.kind == EndpointKind.lan &&
          (p.latencyMs ?? 1 << 30) <= lanCutoff)
      ? 0
      : 1;
  ok.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
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
    final why = picked.kind == EndpointKind.lan ? '局域网优先' : '按延迟择优';
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
