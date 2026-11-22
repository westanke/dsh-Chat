/// 主机直连（含候选探活/失败换地址），连接页与启动自动连接共用。
///
/// 为什么不放在连接页里：启动路径（main.dart 的 _autoConnect）也要同样的
/// 「先探活、再择优、记住上次地址」逻辑，复制一份必然走散（IKX5KQ）。
library;

import 'endpoint_select.dart';
import 'gateway.dart';
import 'hosts.dart';

/// 连接成功的结果：网关 + 诊断（探了哪几条、选了哪条、为什么）。
class HostConnectResult {
  const HostConnectResult({
    required this.gateway,
    required this.host,
    this.selection,
  });

  final GatewayClient gateway;

  /// 写回后的主机记录（baseUrl=本次成功地址，preferredEndpoint 同步）。
  final DshHost host;

  /// 单条地址的老码没有探活，这里是 null。
  final EndpointSelection? selection;

  /// 一句诊断：给连接页/日志看「试了哪几条、哪条成了」。
  String get note => selection?.note ?? '单地址直连 ${gateway.baseUrl}';
}

/// 连接失败：把探活诊断一起带出来（否则用户只知道「连不上」）。
class HostConnectException implements Exception {
  HostConnectException(this.message, {this.note = ''});

  final String message;
  final String note;

  @override
  String toString() => note.isEmpty ? message : '$message；$note';
}

/// 探活择优后连接；失败按候选表轮换重试（每条最多试一次）。
/// 成功后把本次地址写回主机记录，下次启动先试它。
Future<HostConnectResult> connectHost(
  DshHost host, {
  Duration probeTimeout = kEndpointProbeTimeout,
}) async {
  final token = host.token;
  if (token == null || token.isEmpty) {
    throw HostConnectException('这条记录没有配对 token，请重新配对');
  }
  final candidates = host.candidates;
  EndpointSelection? selection;
  var target = host.baseUrl;
  if (candidates.length > 1) {
    selection = await selectEndpoint(
      candidates,
      preferred: host.preferredEndpoint ?? host.baseUrl,
      timeout: probeTimeout,
    );
    if (selection.chosen != null) target = selection.chosen!;
  }
  return _retry(
    host: host,
    token: token,
    candidates: candidates,
    start: target,
    selection: selection,
    failures: <String>[],
  );
}

/// 从 [start] 起按候选表继续试（每条一次），成功则写回主机记录。
Future<HostConnectResult> _retry({
  required DshHost host,
  required String token,
  required List<String> candidates,
  required String start,
  required EndpointSelection? selection,
  required List<String> failures,
}) async {
  var target = start;
  final tried = <String>{};
  while (!tried.contains(target)) {
    tried.add(target);
    final gateway = GatewayClient(baseUrl: target)..token = token;
    gateway.setEndpointCandidates(candidates);
    try {
      await gateway.connect();
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = host.copyWith(
        baseUrl: gateway.baseUrl,
        preferredEndpoint: gateway.baseUrl,
        lastUsedAt: now,
      );
      await DshHosts.upsert(updated);
      return HostConnectResult(
        gateway: gateway,
        host: updated,
        selection: selection,
      );
    } on Object catch (e) {
      failures.add('$target：$e');
      gateway.dispose();
      final rotated = gateway.rotateEndpoint();
      target = gateway.baseUrl;
      if (!rotated) break;
    }
  }
  throw HostConnectException(
    '连接失败：${failures.join('；')}',
    note: selection?.note ?? '',
  );
}
