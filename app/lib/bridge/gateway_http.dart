/// GatewayClient 的 REST 下载（附件 / 图片交接 / 子会话历史共用）。
/// 拆出原因：宪法 §7 单文件 ≤500 行（gateway.dart WS 帧面已近上限）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gateway.dart';

/// GET {gateway.baseUrl}{path}，Bearer token 鉴权，30s 超时，返回原始字节。
/// attachmentId 里的冒号已由调用方 percent-encode（sha256:`<hex>`）。
Future<List<int>> gatewayHttpBytes(GatewayClient gateway, String path) async {
  final token = gateway.token;
  if (token == null || token.isEmpty) {
    throw RequestException('NO_TOKEN', '尚未配对');
  }
  final base = gateway.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse('$base$path');
  final client = http.Client();
  try {
    final resp = await client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200) return resp.bodyBytes;
    throw RequestException(
      'HTTP_${resp.statusCode}',
      '附件下载失败（HTTP ${resp.statusCode}）',
    );
  } on TimeoutException {
    throw RequestException('TIMEOUT', '附件下载超时');
  } finally {
    client.close();
  }
}

/// GET {gateway.baseUrl}{path}，应答按 JSON 解为 Map（第四轮反馈 3：
/// 子会话历史只读窄口 GET /chat/sessions/{leadId}/subagents/{subagentId}/messages）。
/// 404 → SUBAGENT_404（成员未背书/会话不存在），调用方按业务提示。
Future<Map<String, dynamic>> gatewayHttpJson(
  GatewayClient gateway,
  String path,
) async {
  final token = gateway.token;
  if (token == null || token.isEmpty) {
    throw RequestException('NO_TOKEN', '尚未配对');
  }
  final base = gateway.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse('$base$path');
  final client = http.Client();
  try {
    final resp = await client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw RequestException(
      resp.statusCode == 404 ? 'SUBAGENT_404' : 'HTTP_${resp.statusCode}',
      resp.statusCode == 404 ? '子会话不存在或不可见' : '请求失败（HTTP ${resp.statusCode}）',
    );
  } on TimeoutException {
    throw RequestException('TIMEOUT', '请求超时');
  } finally {
    client.close();
  }
}
