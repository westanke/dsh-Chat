/// PendingRegistry / 语义化 close 的回归用例。
///
/// 这些是「协议对齐」里最容易悄悄退化的一层：挂起表按 requestId 关联错了，
/// 症状是请求超时而不是报错；4001 吊销被当普通掉线，症状是无限重连。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dshchat/bridge/gateway_events.dart';
import 'package:dshchat/bridge/gateway_pending.dart';

void main() {
  group('PendingRegistry', () {
    test('add/take：按 requestId 取出，取出后表里不再有', () {
      final reg = PendingRegistry();
      final c = Completer<Map<String, dynamic>>();
      reg.add('req-1', 'history', c);
      expect(reg.length, 1);
      final p = reg.take('req-1');
      expect(p, isNotNull);
      expect(p!.type, 'history');
      expect(reg.length, 0);
      expect(reg.take('req-1'), isNull);
      expect(reg.take(null), isNull);
    });

    test('failOfType：只拒同类型的挂起请求（error 帧无 requestId 时按 requestType 兜底）',
        () {
      final reg = PendingRegistry();
      final h = Completer<Map<String, dynamic>>();
      final m = Completer<Map<String, dynamic>>();
      reg.add('r1', 'history', h);
      reg.add('r2', 'models', m);
      reg.failOfType('history', 'NOT_IMPLEMENTED', '不支持');
      expect(h.isCompleted, isTrue);
      expect(m.isCompleted, isFalse);
      expect(reg.length, 1);
    });

    test('failAll：全拒且清表；已完成的不再重复 completeError（防未捕获异步异常）',
        () {
      final reg = PendingRegistry();
      final a = Completer<Map<String, dynamic>>();
      final b = Completer<Map<String, dynamic>>();
      reg.add('a', 'history', a);
      reg.add('b', 'models', b);
      a.complete(<String, dynamic>{});
      reg.failAll('连接已断开');
      expect(reg.length, 0);
      expect(a.isCompleted, isTrue);
      expect(b.isCompleted, isTrue);
    });

    test('fail：挂 catchError 兜底后再 completeError，无人 await 也不冒异常', () async {
      final reg = PendingRegistry();
      final c = Completer<Map<String, dynamic>>();
      reg.add('x', 'history', c);
      final p = reg.take('x')!;
      PendingRegistry.fail(p, RequestException('UPSTREAM', '上游错误'));
      // 不 await 也不挂 handler：若实现先 completeError 会在这里抛。
      await Future<void>.delayed(Duration.zero);
      expect(p.completer.isCompleted, isTrue);
    });
  });

  group('LinkClosedEvent', () {
    test('4001 = revoked、1009 = frameTooLarge、1000 都不是', () {
      expect(LinkClosedEvent(4001, 'Device revoked').revoked, isTrue);
      expect(LinkClosedEvent(4001, 'Device revoked').frameTooLarge,
          isFalse);
      expect(LinkClosedEvent(1009, 'too large').frameTooLarge, isTrue);
      expect(LinkClosedEvent(1009, 'too large').revoked, isFalse);
      expect(LinkClosedEvent(1000, 'bye').revoked, isFalse);
      expect(LinkClosedEvent(1000, 'bye').frameTooLarge, isFalse);
    });
  });
}
