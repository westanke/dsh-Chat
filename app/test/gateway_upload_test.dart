/// WS 附件上传（open → chunk → finish）的纯函数与帧顺序测试。
library;

import 'dart:convert';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/gateway_upload.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<({String type, Map<String, dynamic> payload})> requests = [];
  final Map<String, Map<String, dynamic> Function(Map<String, dynamic>)>
  replies = {};
  final Map<String, RequestException> errors = {};

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type: type, payload: Map<String, dynamic>.from(payload)));
    final error = errors[type];
    if (error != null) throw error;
    final reply = replies[type];
    if (reply == null) {
      throw RequestException('UNKNOWN_TYPE', 'unknown frame $type');
    }
    return reply(payload);
  }

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) => request(type, payload);
}

/// 按偏移自动回 nextOffset 的桥。
void _wireChunks(_FakeGateway gw, {int? chunkBytes = 2}) {
  gw.replies['file-upload-open'] = (_) => <String, dynamic>{
    'uploadId': 'u1',
    'chunkBytes': ?chunkBytes,
  };
  gw.replies['file-upload-chunk'] = (p) => <String, dynamic>{
    'nextOffset': (p['offset'] as int) + base64Decode(p['data'] as String).length,
  };
  gw.replies['file-upload-finish'] = (_) => <String, dynamic>{
    'receiptId': 'rcpt-1',
  };
}

void main() {
  group('纯函数', () {
    test('sha256 小写 hex（桥要求 64 位）', () {
      expect(
        attachmentSha256(utf8.encode('hello')),
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
      expect(attachmentSha256(const []), hasLength(64));
    });

    test('分片大小：默认 256KiB，桥更小则听桥的', () {
      expect(attachmentChunkSize(null), kAttachmentChunkBytes);
      expect(attachmentChunkSize(0), kAttachmentChunkBytes);
      expect(attachmentChunkSize(-1), kAttachmentChunkBytes);
      expect(attachmentChunkSize(1024), 1024);
      expect(attachmentChunkSize(kAttachmentChunkBytes * 2), kAttachmentChunkBytes);
    });

    test('切分：按块长切开，末块收尾', () {
      final chunks = splitAttachmentChunks([1, 2, 3, 4, 5], 2);
      expect(chunks.map((c) => c.toList()), [
        [1, 2],
        [3, 4],
        [5],
      ]);
      expect(splitAttachmentChunks([], 2), isEmpty);
      expect(() => splitAttachmentChunks([1], 0), throwsArgumentError);
    });
  });

  group('uploadAttachmentWs', () {
    test('open → 逐块 chunk（offset 精确）→ finish，返回 receiptId', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['file-upload-open'];
      _wireChunks(gw);
      final bytes = utf8.encode('hello');

      final receipt = await uploadAttachmentWs(
        gw,
        sessionId: 's1',
        name: 'hello.txt',
        bytes: bytes,
      );

      expect(receipt, 'rcpt-1');
      expect(gw.requests.map((r) => r.type), [
        'file-upload-open',
        'file-upload-chunk',
        'file-upload-chunk',
        'file-upload-chunk',
        'file-upload-finish',
      ]);
      final open = gw.requests.first.payload;
      expect(open['sessionId'], 's1');
      expect(open['name'], 'hello.txt');
      expect(open['size'], 5);
      expect(open['sha256'], attachmentSha256(bytes));

      final chunks = gw.requests
          .where((r) => r.type == 'file-upload-chunk')
          .toList();
      expect(chunks.map((c) => c.payload['offset']), [0, 2, 4]);
      expect(chunks.map((c) => c.payload['uploadId']), ['u1', 'u1', 'u1']);
      expect(chunks[0].payload['data'], base64Encode([104, 101]));
      expect(chunks[2].payload['data'], base64Encode([111]));
      expect(gw.requests.last.payload, {'uploadId': 'u1'});
    });

    test('桥下发更小 chunkBytes → 按桥的切', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['file-upload-open'];
      _wireChunks(gw, chunkBytes: 2);
      await uploadAttachmentWs(
        gw,
        sessionId: 's1',
        name: 'x',
        bytes: [1, 2, 3],
      );
      expect(
        gw.requests
            .where((r) => r.type == 'file-upload-chunk')
            .map((r) => r.payload['offset']),
        [0, 2],
      );
    });

    test('空文件：只 open + finish，不发 chunk', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['file-upload-open'];
      _wireChunks(gw);

      expect(
        await uploadAttachmentWs(
          gw,
          sessionId: 's1',
          name: 'empty.txt',
          bytes: const [],
        ),
        'rcpt-1',
      );
      expect(gw.requests.map((r) => r.type), [
        'file-upload-open',
        'file-upload-finish',
      ]);
    });

    test('open 失败 → 不继续发 chunk / finish', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['file-upload-open'];
      gw.errors['file-upload-open'] = RequestException('NO_FILE', '文件为空');

      await expectLater(
        uploadAttachmentWs(
          gw,
          sessionId: 's1',
          name: 'x',
          bytes: [1, 2],
        ),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_FILE'),
        ),
      );
      expect(gw.requests.map((r) => r.type), ['file-upload-open']);
    });

    test('chunk 失败 → 不发 finish', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['file-upload-open'];
      _wireChunks(gw);
      gw.errors['file-upload-chunk'] = RequestException('BAD_OFFSET', '偏移不对');

      await expectLater(
        uploadAttachmentWs(
          gw,
          sessionId: 's1',
          name: 'x',
          bytes: [1, 2, 3, 4],
        ),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'BAD_OFFSET'),
        ),
      );
      expect(gw.requests.map((r) => r.type), [
        'file-upload-open',
        'file-upload-chunk',
      ]);
    });

    test('nextOffset 没前进 → PROTOCOL，且不发 finish', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['file-upload-open'];
      gw.replies['file-upload-open'] = (_) => {'uploadId': 'u1', 'chunkBytes': 2};
      gw.replies['file-upload-chunk'] = (_) => {'nextOffset': 0};

      await expectLater(
        uploadAttachmentWs(
          gw,
          sessionId: 's1',
          name: 'x',
          bytes: [1, 2],
        ),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'PROTOCOL'),
        ),
      );
      expect(gw.requests.map((r) => r.type), [
        'file-upload-open',
        'file-upload-chunk',
      ]);
    });

    test('finish 缺 receiptId → PROTOCOL', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['file-upload-open'];
      _wireChunks(gw);
      gw.replies['file-upload-finish'] = (_) => <String, dynamic>{};

      await expectLater(
        uploadAttachmentWs(
          gw,
          sessionId: 's1',
          name: 'x',
          bytes: [1],
        ),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'PROTOCOL'),
        ),
      );
    });

    test('没声明 file-upload-open → NOT_SUPPORTED，一个帧都不发', () async {
      final gw = _FakeGateway();
      await expectLater(
        uploadAttachmentWs(
          gw,
          sessionId: 's1',
          name: 'x',
          bytes: [1],
        ),
        throwsA(
          isA<RequestException>()
              .having((e) => e.code, 'code', 'NOT_SUPPORTED'),
        ),
      );
      expect(gw.requests, isEmpty);
    });
  });
}
