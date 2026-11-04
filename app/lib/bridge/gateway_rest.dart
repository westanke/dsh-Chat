/// GatewayClient 的工作区管理 REST 通道（真机反馈 2026-11-04 第 7 项）。
/// 拆出原因：宪法 §7 单文件 ≤500 行（gateway.dart 已超线）。
///
/// 为什么走 REST 而不是 WS workspace-create 帧：那帧要宿主**绝对路径**
/// （matchAuthorizedRootResolved），客户端拿不到授权根绝对路径；REST
/// POST /chat/workspaces 的 body.path 是根内相对路径（WirePath），
/// bridge 内部换算——这是纯手机端可用的建工作区通道。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gateway.dart';

/// REST POST /api/v1/chat/workspaces（登记工作区；chat.write scope）。
/// [path] 是授权根内相对路径；目录必须已存在（createWorkspace lstat 校验），
/// 幂等返回既有工作区。返回 workspaceId。
Future<String> gatewayCreateWorkspace(
  GatewayClient gateway, {
  required String rootId,
  required String path,
}) async {
  final resp = await _restJson(
    gateway,
    method: 'POST',
    path: '/api/v1/chat/workspaces',
    body: {'rootId': rootId, 'path': path},
    fail: '工作区创建失败',
    timeout: '工作区创建超时',
  );
  final ws = resp is Map ? resp['workspace'] : null;
  final id = ws is Map ? ws['workspaceId'] ?? ws['id'] : null;
  if (id is! String || id.isEmpty) {
    throw RequestException('BAD_REPLY', '工作区创建应答缺 id');
  }
  return id;
}

/// REST PATCH /api/v1/chat/workspaces/{id}（改工作区名，chat.write scope）。
/// 内核自定的 title 不合意时用来落成「手机会话」。
Future<void> gatewayRenameWorkspace(
  GatewayClient gateway,
  String workspaceId,
  String title,
) async {
  await _restJson(
    gateway,
    method: 'PATCH',
    path: '/api/v1/chat/workspaces/${Uri.encodeComponent(workspaceId)}',
    body: {'title': title},
    fail: '工作区改名失败',
    timeout: '工作区改名超时',
    okCodes: const [200],
  );
}

/// REST JSON 请求骨架：Bearer token + 30s 超时 + 状态码校验。
/// 返回解码后的 JSON 体（无 body/空 body 回空 Map）。
Future<Object?> _restJson(
  GatewayClient gateway, {
  required String method,
  required String path,
  required Map<String, String> body,
  required String fail,
  required String timeout,
  List<int> okCodes = const [200, 201],
}) async {
  final token = gateway.token;
  if (token == null || token.isEmpty) {
    throw RequestException('NO_TOKEN', '尚未配对');
  }
  final base = gateway.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse('$base$path');
  final client = http.Client();
  try {
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final resp = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    if (!okCodes.contains(resp.statusCode)) {
      throw RequestException(
        'HTTP_${resp.statusCode}',
        '$fail（HTTP ${resp.statusCode}）',
      );
    }
    if (resp.body.isEmpty) return const {};
    return jsonDecode(resp.body);
  } on TimeoutException {
    throw RequestException('TIMEOUT', timeout);
  } finally {
    client.close();
  }
}
