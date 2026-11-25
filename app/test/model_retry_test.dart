// 模型重试（内核 `llm/retry`）的装配与渲染：
// 真机反馈 2026-11-25 —— 桌面端有「已重试模型请求（1/5）· 1s」，客户端
// 整条丢弃（装配器不认 `llm/retry` / `llm/retry-started`）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/design/app_settings.dart';
import 'package:dshchat/ui/chat_rows.dart';

Map<String, dynamic> _ev(
  String type,
  int seq,
  Map<String, dynamic> data,
) => {'type': type, 'seq': seq, 'time': 1000 + seq, 'data': data};

void main() {
  group('HistoryPage 装配模型重试', () {
    test('llm/retry 生成一条 role=retry 消息并带明细', () {
      final page = HistoryPage.fromEvents([
        _ev('user/message', 1, {
          'content': 'hi',
          'source': {'kind': 'user'},
        }),
        _ev('llm/retry', 2, {
          'retryId': 'r1',
          'retry': 1,
          'maxRetries': 5,
          'delayMs': 536,
          'failure': {
            'code': 'SERVER',
            'message': 'loomy: <html>504 Gateway Time-out</html>',
          },
        }),
      ]);
      final retries = page.items.where((m) => m.isRetry).toList();
      expect(retries.length, 1);
      final info = retries.single.retryInfo!;
      expect(info.retryId, 'r1');
      expect(info.retry, 1);
      expect(info.maxRetries, 5);
      expect(info.maximum, 5);
      expect(info.delayMs, 536);
      expect(info.seconds, 1);
      expect(info.failureCode, 'SERVER');
      expect(info.failureMessage, contains('504 Gateway Time-out'));
      expect(info.started, isFalse);
      expect(info.label, '正在重试模型请求');
    });

    test('llm/retry-started 把同一跳标记为已重试', () {
      final page = HistoryPage.fromEvents([
        _ev('llm/retry', 2, {
          'retryId': 'r1',
          'retry': 1,
          'maxRetries': 5,
          'delayMs': 536,
        }),
        _ev('llm/retry-started', 3, {'retryId': 'r1', 'retry': 1}),
      ]);
      final retries = page.items.where((m) => m.isRetry).toList();
      expect(retries.length, 1);
      expect(retries.single.retryInfo!.started, isTrue);
      expect(retries.single.retryInfo!.label, '已重试模型请求');
    });

    test('同一 retryId 的多次跳各成一条（retry 递增）', () {
      final page = HistoryPage.fromEvents([
        _ev('llm/retry', 2, {'retryId': 'r1', 'retry': 1, 'maxRetries': 5}),
        _ev('llm/retry', 3, {'retryId': 'r1', 'retry': 2, 'maxRetries': 5}),
      ]);
      final retries = page.items.where((m) => m.isRetry).toList();
      expect(retries.length, 2);
      expect(retries.map((m) => m.retryInfo!.retry), [1, 2]);
    });

    test('轮结束仍未 started 的重试标记为已取消', () {
      final page = HistoryPage.fromEvents([
        _ev('llm/retry', 2, {'retryId': 'r1', 'retry': 1, 'maxRetries': 5}),
        _ev('turn/end', 3, {'reason': {'kind': 'completed'}}),
      ]);
      final info = page.items.firstWhere((m) => m.isRetry).retryInfo!;
      expect(info.cancelled, isTrue);
      expect(info.label, '模型请求重试已取消');
    });
  });

  group('行派生', () {
    test('role=retry 的消息派生出 RetryRow', () {
      final message = ChatMessage(
        role: 'retry',
        text: '',
        seq: 7,
        retryInfo: ModelRetryInfo(retryId: 'r1', retry: 1, maxRetries: 5),
      );
      final rows = deriveRows(
        ChatRowsInput(
          messages: [message],
          folded: FoldedReplies.all,
          streaming: false,
          hasMoreHistory: false,
          historyTruncated: false,
          streamingProcess: null,
          maxTokensNotice: false,
          linkError: null,
        ),
      );
      expect(rows.whereType<RetryRow>().length, 1);
      expect(rows.whereType<RetryRow>().single.key, 'rtr1');
    });
  });
}
