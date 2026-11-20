/// mention 文本格式的单测（2026-11-21 工单 3、4）。
///
/// 两边语法都以内核为准：
/// - 文件：`@path`，含空白/引号加双引号，目录以 `/` 结尾（官方
///   `formatFileMention`）；
/// - 会话：`@[标题](dsh-session:<id>)`（内核 `renderSessionMention`）。
library;

import 'package:dshchat/ui/composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fileMentionText', () {
    test('普通文件：@path', () {
      expect(fileMentionText('lib/ui/chat_page.dart', directory: false),
          '@lib/ui/chat_page.dart');
    });

    test('目录补尾斜杠：@dir/', () {
      expect(fileMentionText('lib/ui', directory: true), '@lib/ui/');
      expect(fileMentionText('lib/ui/', directory: true), '@lib/ui/');
    });

    test('含空白的路径加双引号', () {
      expect(fileMentionText('my docs/a.md', directory: false),
          '@"my docs/a.md"');
    });

    test('文件名的引号被转义', () {
      expect(fileMentionText('a"b.md', directory: false), '@"a\\"b.md"');
    });
  });

  group('sessionMentionText', () {
    test('标准形态 @[标题](dsh-session:id)', () {
      expect(sessionMentionText('修 1002', 'abc-123'),
          '@[修 1002](dsh-session:abc-123)');
    });

    test('标题里的 ] 换成全角，避免提前闭合', () {
      expect(sessionMentionText('a]b', 's1'), '@[a］b](dsh-session:s1)');
    });

    test('标题为空回退成 id', () {
      expect(sessionMentionText('   ', 's1'), '@[s1](dsh-session:s1)');
    });
  });
}
