/// WS 附件上传：`file-upload-open` → N×`file-upload-chunk` → `finish`。
///
/// 协议事实来源 dsh-remote-bridge `src/host/ws-file-transfer.ts`：
/// - open `{sessionId,name,size,sha256}` → `{uploadId,chunkBytes,maxBytes,…}`
/// - chunk `{uploadId,offset,data(base64)}` → `{nextOffset,…}`
/// - finish `{uploadId}` → `{receiptId,file:{attachmentId,name,bytes},…}`
///
/// 这里只提供能力，不接现有图片发送路径（composer 走 REST 直传，暂不替换）。
/// 纯计算部分（sha256 / 分片）独立成函数，便于单测且不依赖网关。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'gateway.dart';

/// 默认分片 256 KiB（桥的 chunkBytes 更小时按桥的来）。
const int kAttachmentChunkBytes = 256 * 1024;

/// 附件字节的 SHA-256 小写 hex（桥要求 64 位）。
String attachmentSha256(List<int> bytes) => sha256.convert(bytes).toString();

/// 实际分片大小：桥下发的 `chunkBytes` 为正且更小时取它，否则 256 KiB。
int attachmentChunkSize(int? advertised) {
  if (advertised == null || advertised <= 0) return kAttachmentChunkBytes;
  return advertised < kAttachmentChunkBytes ? advertised : kAttachmentChunkBytes;
}

/// 按 [chunkBytes] 切分字节（返回视图副本，避免调用方后续改原数组）。
List<Uint8List> splitAttachmentChunks(List<int> bytes, int chunkBytes) {
  if (chunkBytes <= 0) {
    throw ArgumentError.value(chunkBytes, 'chunkBytes', '必须为正数');
  }
  final out = <Uint8List>[];
  for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
    final end = offset + chunkBytes < bytes.length
        ? offset + chunkBytes
        : bytes.length;
    out.add(Uint8List.fromList(bytes.sublist(offset, end)));
  }
  return out;
}

/// 走 WS 上传一个附件，返回桥的 `receiptId`。
///
/// [name] 是叶子文件名（桥要求 1..255 且不含路径分隔符）；[bytes] 原样上传，
/// sha256 由本地计算。任一帧失败抛 [RequestException]；open 失败不会继续发
/// chunk，chunk 失败不会发 finish。
Future<String> uploadAttachmentWs(
  GatewayClient gateway, {
  required String sessionId,
  required String name,
  required List<int> bytes,
}) async {
  if (!gateway.hasFrame('file-upload-open')) {
    throw RequestException(
      'NOT_SUPPORTED',
      '当前主机不支持 file-upload-open 帧（hello.frames 里没有它）',
    );
  }
  final opened = await gateway.request('file-upload-open', {
    'sessionId': sessionId,
    'name': name,
    'size': bytes.length,
    'sha256': attachmentSha256(bytes),
  });
  final uploadId = opened['uploadId'];
  if (uploadId is! String || uploadId.isEmpty) {
    throw RequestException('PROTOCOL', 'file-upload-open 应答缺 uploadId');
  }
  final chunkBytes = attachmentChunkSize(_asInt(opened['chunkBytes']));
  var offset = 0;
  while (offset < bytes.length) {
    final end = offset + chunkBytes < bytes.length
        ? offset + chunkBytes
        : bytes.length;
    final chunk = bytes.sublist(offset, end);
    final reply = await gateway.request('file-upload-chunk', {
      'uploadId': uploadId,
      'offset': offset,
      'data': base64Encode(chunk),
    });
    final next = _asInt(reply['nextOffset']);
    if (next != end) {
      throw RequestException(
        'PROTOCOL',
        'file-upload-chunk 应答 nextOffset=$next，期望 $end',
      );
    }
    offset = next!;
  }
  final done = await gateway.request('file-upload-finish', {
    'uploadId': uploadId,
  });
  final receiptId = done['receiptId'];
  if (receiptId is! String || receiptId.isEmpty) {
    throw RequestException('PROTOCOL', 'file-upload-finish 应答缺 receiptId');
  }
  return receiptId;
}

int? _asInt(Object? raw) => raw is int ? raw : (raw is num ? raw.toInt() : null);
