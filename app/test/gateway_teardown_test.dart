// 握手期卡住的地址：TCP 连上了但服务端永不回 HTTP 升级响应。
// 以前 connectTimeout 到点后，_teardown 里的 `await ws.sink.close()` 会一直等
// 这条没完成的握手 → 整个连接流程挂死（真机表现为按钮变灰、无报错）。
import 'dart:io';

import 'package:dshchat/bridge/gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('永远不回升级响应的地址：超时到点后必须返回，不挂在 teardown', () async {
    // 只 accept、不写任何字节：WebSocket 升级请求会一直等。
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final held = <Socket>[];
    server.listen(held.add);

    final gw = GatewayClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      connectTimeout: const Duration(milliseconds: 300),
      helloTimeout: const Duration(milliseconds: 300),
    );
    final sw = Stopwatch()..start();
    Object? error;
    try {
      await gw.pair(code: 'ABC12', newDeviceId: 'dev-1', name: 'test');
    } catch (e) {
      error = e;
    }
    sw.stop();

    expect(error, isA<RequestException>());
    expect(
      sw.elapsedMilliseconds,
      lessThan(5000),
      reason: 'teardown 不该为了关一条没握手的连接而无限等',
    );
    for (final s in held) {
      s.destroy();
    }
    await server.close();
  }, timeout: const Timeout(Duration(seconds: 15)));
}
