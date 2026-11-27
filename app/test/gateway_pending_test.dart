/// PendingRegistry / 语义化 close 的回归用例。
///
/// 这些是「协议对齐」里最容易悄悄退化的一层：挂起表按 requestId 关联错了，
/// 症状是请求超时而不是报错；4001 吊销被当普通掉线，症状是无限重连。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dshchat/bridge/gateway.dart';

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

    test('1009 带本次连接实际上限；1013 = 服务端忙', () {
      final e = LinkClosedEvent(1009, 'too large', limitBytes: 2 * 1024 * 1024);
      expect(e.frameTooLarge, isTrue);
      expect(e.limitBytes, 2097152);
      expect(frameLimitText(e.limitBytes!), '2048 KiB');
      expect(frameLimitHint(e.limitBytes!), contains('2048 KiB'));
      expect(frameLimitHint(e.limitBytes!), contains('附件'));
      expect(LinkClosedEvent(1013, 'busy').serverBusy, isTrue);
    });
  });

  group('hello.maxFrameBytes', () {
    test('只接受正整数字节数；缺字段/非法值回退 null（由连接状态兜底默认值）', () {
      expect(parseMaxFrameBytes(2097152), 2097152);
      expect(parseMaxFrameBytes(1), 1);
      expect(parseMaxFrameBytes(null), isNull);
      expect(parseMaxFrameBytes(0), isNull);
      expect(parseMaxFrameBytes(-1), isNull);
      expect(parseMaxFrameBytes('1048576'), isNull);
      expect(parseMaxFrameBytes(1.5), isNull);
      expect(defaultMaxFrameBytes, 1024 * 1024);
    });

    test('人话单位按 KiB 向上取整，不硬编码 1 MiB', () {
      expect(frameLimitText(1024), '1 KiB');
      expect(frameLimitText(1025), '2 KiB');
      expect(frameLimitText(1024 * 1024), '1024 KiB');
      expect(frameLimitText(3 * 1024 * 1024), '3072 KiB');
    });
  });

  group('RequestException 协议字段', () {
    test('retryable/details/statusCode 原样保留，429 可判限流并算等待秒数', () {
      final e = RequestException(
        'RATE_LIMITED',
        '请求过于频繁',
        retryable: true,
        statusCode: 429,
        details: {'retryAfterMs': 2500},
      );
      expect(e.retryable, isTrue);
      expect(e.statusCode, 429);
      expect(e.rateLimited, isTrue);
      expect(e.retryAfterMs, 2500);
      expect(e.retryAfterSeconds, 3); // 向上取整
    });

    test('缺省 retryable=false；details 形状不对时不炸', () {
      final e = RequestException('UPSTREAM', '上游错误');
      expect(e.retryable, isFalse);
      expect(e.rateLimited, isFalse);
      expect(e.retryAfterMs, isNull);
      expect(e.retryAfterSeconds, isNull);
      final bad = RequestException(
        'RATE_LIMITED',
        'x',
        details: {'retryAfterMs': 'soon'},
      );
      expect(bad.retryAfterMs, isNull);
      final numMs = RequestException(
        'RATE_LIMITED',
        'x',
        details: {'retryAfterMs': 1500.0},
      );
      expect(numMs.retryAfterMs, 1500);
    });
  });
}
