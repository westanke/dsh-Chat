/// 请求路径纯函数回归：bridge 对 query 参数的强制要求写在这里，改错就有用例红。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dshchat/bridge/gateway_api.dart';

void main() {
  test('imageHandoffPath：name 与 sessionId 两个 query 都必须在', () {
    final path = imageHandoffPath('a1b2c3.png', 'sess-1');
    expect(path, startsWith('/api/v1/image-handoff?'));
    expect(path, contains('name=a1b2c3.png'));
    expect(path, contains('sessionId=sess-1'));
    // 缺 sessionId 时 bridge 回 400 BODY_INVALID（companion 踩过的坑）
    expect(path.contains('sessionId='), isTrue);
  });

  test('imageHandoffPath：特殊字符按 percent-encode（sha256: 的冒号、空格）', () {
    expect(imageHandoffPath('sha256:ab c.png', 's 1'),
        contains('name=sha256%3Aab%20c.png'));
    expect(imageHandoffPath('a.png', 's 1'), contains('sessionId=s%201'));
  });

  test('sessionsFrame：默认空帧；归档开关发 archived:true（桥没有 includeArchived）', () {
    expect(sessionsFrame(), isEmpty);
    expect(sessionsFrame(archived: false), isEmpty);
    expect(sessionsFrame(archived: true), {'archived': true});
    expect(sessionsFrame(archived: true).containsKey('includeArchived'), isFalse);
  });
}
