/// 大消息通道选择（真机反馈 2026-11-28）的纯函数回归。
///
/// 背景：相册原图 base64 后 2.5–9 MB，恒超桥默认 1 MiB `maxFrameBytes`；
/// 老实现只有 WS `message` 帧一条路，本地预检直接抛
/// 「请求内容超过连接上限 1024 KiB」。修法是发之前用 `messageFrameBytes`
/// 估整帧字节数，超了就改走 REST 大消息通道。
///
/// 这里锁两件事：
/// 1. 估算与 `gateway._sendRaw` 的判据同形（utf8(jsonEncode(整帧))），
///    含 `type`/`requestId` 帧头，不会把「快超了」的消息误判成装得下；
/// 2. body 构造与 `sendText` 共用 `messageFrameBody`，字段漏一个就会红。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dshchat/bridge/content.dart';
import 'package:dshchat/bridge/gateway.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Asia/Shanghai';

String _b64(int bytes) => 'A' * bytes;

void main() {
  test('messageFrameBody：文本 + 图片字段齐全，name 可选，sessionId 为空不发', () {
    final body = messageFrameBody(
      parts: [
        PromptPart.text('看图'),
        PromptPart.image('image/jpeg', _b64(16), name: 'IMG_1.jpg'),
        PromptPart.image('image/png', _b64(8)),
      ],
      mode: 'queue',
      clientTimeZone: _zone,
    );
    expect(body.containsKey('sessionId'), isFalse);
    expect(body['mode'], 'queue');
    expect(body['clientTimeZone'], _zone);
    final content = body['content'] as List;
    expect(content, hasLength(3));
    expect((content[0] as Map)['type'], 'text');
    expect((content[1] as Map)['name'], 'IMG_1.jpg');
    expect((content[2] as Map).containsKey('name'), isFalse);
    expect((content[2] as Map)['mediaType'], 'image/png');
  });

  test('messageFrameBody：带 sessionId 时照发（REST/WS 共用同一份 shape）', () {
    final body = messageFrameBody(
      parts: [PromptPart.text('hi')],
      mode: 'steer',
      clientTimeZone: _zone,
      sessionId: 'sess-1',
    );
    expect(body['sessionId'], 'sess-1');
    expect(body['mode'], 'steer');
  });

  test('messageFrameBytes：base64 总量主导，1 MiB 帧上限的边界落在 1 MiB 附近', () {
    final limit = 1024 * 1024;
    // 空白消息：只有帧头，远小于 1 MiB。
    final empty = messageFrameBytes(
      const <PromptPart>[],
      mode: 'queue',
      clientTimeZone: _zone,
    );
    expect(empty, lessThan(320));

    // 494 168 B base64（实测 370 KB PNG 截图）装得下。
    final shot = messageFrameBytes(
      [PromptPart.image('image/png', _b64(494168), name: 'shot.png')],
      mode: 'queue',
      clientTimeZone: _zone,
    );
    expect(shot, lessThan(limit));
    expect(shot, greaterThan(494168));

    // 2.5 MB base64（1.87 MB 原图）装不下 —— 就是要让 send() 改走 REST。
    final photo = messageFrameBytes(
      [PromptPart.image('image/jpeg', _b64(2500000), name: 'IMG_1.jpg')],
      mode: 'queue',
      clientTimeZone: _zone,
    );
    expect(photo, greaterThan(limit));
    // 余量（requestId 猜测）不该大于 1 KiB，否则判定会偏离真实帧。
    expect(photo - 2500000, lessThan(1024));
  });

  test('messageFrameBytes：sessionId 会让帧变大（估算包含帧头字段）', () {
    const sid = 'sess-abcdefgh';
    final withSid = messageFrameBytes(
      [PromptPart.text('x')],
      mode: 'queue',
      clientTimeZone: _zone,
      sessionId: sid,
    );
    final without = messageFrameBytes(
      [PromptPart.text('x')],
      mode: 'queue',
      clientTimeZone: _zone,
    );
    expect(withSid - without, '"sessionId":"$sid",'.length);
  });

  test('REST 通道上限：12 MB，超限提示按 MiB 一位小数说明分批发送', () {
    expect(restMessageLimitBytes, 12000000);
    final hint = gatewayRestMessageLimitHint(13 * 1024 * 1024);
    expect(hint, contains('13.0 MiB'));
    expect(hint, contains('11 MiB'));
    expect(hint, contains('分批'));
  });

  test('gatewaySendMessage：POST 到 /messages，body 与 WS 帧同形，202 即成功', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final captured = Completer<Map<String, dynamic>>();
    var seenMethod = '';
    var seenSegments = <String>[];
    var seenAuth = '';
    server.listen((req) async {
      seenMethod = req.method;
      seenSegments = req.uri.pathSegments;
      seenAuth = req.headers.value('authorization') ?? '';
      captured.complete(
        jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>,
      );
      req.response.statusCode = 202;
      req.response.write('{}');
      await req.response.close();
    });
    final gw = GatewayClient(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 't0k3n';
    await gatewaySendMessage(
      gw,
      sessionId: 'sess 1',
      parts: [
        PromptPart.text('看图'),
        PromptPart.image('image/jpeg', 'QUJD', name: 'a.jpg'),
      ],
    );
    final body = await captured.future;
    await server.close(force: true);

    expect(seenMethod, 'POST');
    // sessionId 必须 percent-encode（带空格的 id 不能拼坏路径）
    expect(seenSegments, ['api', 'v1', 'chat', 'sessions', 'sess 1', 'messages']);
    expect(seenAuth, 'Bearer t0k3n');
    expect(body['mode'], 'queue');
    expect(body['clientTimeZone'], isNotEmpty);
    expect(body['clientRequestId'], isA<String>());
    expect((body['clientRequestId'] as String), startsWith('c'));
    final content = body['content'] as List;
    expect(content, hasLength(2));
    expect((content[1] as Map)['data'], 'QUJD');
    expect((content[1] as Map)['mediaType'], 'image/jpeg');
  });

  test('gatewaySendMessage：服务端 413 映射成带状态码的 RequestException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await utf8.decodeStream(req); // 吃完请求体再回，避免对端写失败
      req.response.statusCode = 413;
      req.response.write('{"error":"too large"}');
      await req.response.close();
    });
    final gw = GatewayClient(baseUrl: 'http://127.0.0.1:${server.port}')
      ..token = 't0k3n';
    await expectLater(
      gatewaySendMessage(
        gw,
        sessionId: 's1',
        parts: [PromptPart.text('x')],
      ),
      throwsA(
        isA<RequestException>()
            .having((e) => e.code, 'code', 'HTTP_413')
            .having((e) => e.message, 'message', contains('发送失败')),
      ),
    );
    await server.close(force: true);
  });
}
