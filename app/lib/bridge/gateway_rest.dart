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

/// REST GET /api/v1/roots/resolve?path=<绝对路径>（openapi.yaml:151-177，
/// resolveAbsolutePath；files.read scope）：把 deliverables 事件里的服务器
/// 绝对路径映射进授权根。应答 ResolvedPath{rootId, path(WirePath), kind,
/// size, modifiedAt, contentType}；404=不在授权根（FILE_404）。
Future<ResolvedFile> gatewayResolvePath(
  GatewayClient gateway,
  String absolutePath,
) async {
  final token = gateway.token;
  if (token == null || token.isEmpty) {
    throw RequestException('NO_TOKEN', '尚未配对');
  }
  final base = gateway.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse(
    '$base/api/v1/roots/resolve?path=${Uri.encodeComponent(absolutePath)}',
  );
  final client = http.Client();
  try {
    final resp = await client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw RequestException(
        resp.statusCode == 404 ? 'FILE_404' : 'HTTP_${resp.statusCode}',
        resp.statusCode == 404 ? '文件不在授权目录内' : '路径解析失败（HTTP ${resp.statusCode}）',
      );
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final kind = j['kind'];
    if (kind != 'file') {
      throw RequestException('NOT_FILE', '目标不是文件');
    }
    return ResolvedFile(
      rootId: (j['rootId'] ?? '') as String,
      path: (j['path'] ?? '') as String,
      size: j['size'] as int?,
      contentType: j['contentType'] as String?,
    );
  } on TimeoutException {
    throw RequestException('TIMEOUT', '路径解析超时');
  } finally {
    client.close();
  }
}

/// resolveAbsolutePath 的应答（openapi.yaml:1820-1831，只取客户端要用的字段）。
class ResolvedFile {
  const ResolvedFile({
    required this.rootId,
    required this.path,
    this.size,
    this.contentType,
  });

  final String rootId;

  /// 授权根内相对路径（WirePath）——传回 content 端点用。
  final String path;
  final int? size;
  final String? contentType;
}

/// REST GET /api/v1/roots（listRoots，openapi.yaml:135-149，files.read
/// scope）：本设备授权根清单。Root{id,label,createdAt}，绝对路径不下发。
/// @ 文件补全用：先拿根，再对各根列目录。
Future<List<GatewayRoot>> gatewayListRoots(GatewayClient gateway) async {
  final token = gateway.token;
  if (token == null || token.isEmpty) {
    throw RequestException('NO_TOKEN', '尚未配对');
  }
  final base = gateway.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse('$base/api/v1/roots');
  final client = http.Client();
  try {
    final resp = await client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw RequestException('HTTP_${resp.statusCode}', '授权根列表拉取失败');
    }
    final j = jsonDecode(resp.body);
    final items = j is Map ? j['items'] : null;
    if (items is! List) return const [];
    return [
      for (final it in items)
        if (it is Map)
          GatewayRoot(
            id: (it['id'] ?? '') as String,
            label: (it['label'] ?? '') as String,
          ),
    ];
  } on TimeoutException {
    throw RequestException('TIMEOUT', '授权根列表超时');
  } finally {
    client.close();
  }
}

/// listRoots 应答项（openapi.yaml:1862-1870，只取客户端要用的字段）。
class GatewayRoot {
  const GatewayRoot({required this.id, required this.label});

  final String id;
  final String label;
}

/// REST GET /api/v1/roots/{rootId}/entries?path=`<WirePath>`
/// （listEntries，openapi.yaml:177-200，files.read scope）：懒分页目录页。
/// [wirePath] 传根内相对路径（'' = 根，path-policy.ts:55 空段合法）；返回按
/// 目录优先、名称升序排好的条目（只保留 file/directory，symlink/other 不进
/// @ 补全）。403=无权访问该目录。
Future<List<GatewayEntry>> gatewayListEntries(
  GatewayClient gateway,
  String rootId,
  String wirePath,
) async {
  final token = gateway.token;
  if (token == null || token.isEmpty) {
    throw RequestException('NO_TOKEN', '尚未配对');
  }
  final base = gateway.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse(
    '$base/api/v1/roots/${Uri.encodeComponent(rootId)}/entries'
    '?path=${Uri.encodeComponent(wirePath)}&limit=500',
  );
  final client = http.Client();
  try {
    final resp = await client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw RequestException(
        resp.statusCode == 403 ? 'DIR_403' : 'HTTP_${resp.statusCode}',
        resp.statusCode == 403 ? '目录不可访问' : '目录列表拉取失败',
      );
    }
    final j = jsonDecode(resp.body);
    final entries = j is Map ? j['entries'] : null;
    if (entries is! List) return const [];
    final out = <GatewayEntry>[];
    for (final e in entries) {
      if (e is! Map) continue;
      final kind = (e['kind'] ?? '') as String;
      if (kind != 'file' && kind != 'directory') continue;
      out.add(
        GatewayEntry(
          name: (e['name'] ?? '') as String,
          path: (e['path'] ?? '') as String,
          kind: kind,
        ),
      );
    }
    out.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  } on TimeoutException {
    throw RequestException('TIMEOUT', '目录列表超时');
  } finally {
    client.close();
  }
}

/// listEntries 应答项（FileEntry，openapi.yaml:1872-1881，裁剪字段）。
class GatewayEntry {
  const GatewayEntry({
    required this.name,
    required this.path,
    required this.kind,
  });

  final String name;
  final String path;
  final String kind;

  bool get isDirectory => kind == 'directory';
}

/// REST GET /api/v1/roots/{rootId}/content?path=`<WirePath>`
/// （openapi.yaml:243-286，readContent；files.read scope）：取文件原始字节。
Future<List<int>> gatewayReadFileBytes(
  GatewayClient gateway,
  String rootId,
  String wirePath,
) {
  return gatewayHttpBytes(
    gateway,
    '/api/v1/roots/$rootId/content?path=${Uri.encodeComponent(wirePath)}',
  );
}
