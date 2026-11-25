/// 按会话草稿的回归（对照 chat-demo 的 drafts.ts）。
///
/// 要点：草稿按 sessionId 隔离（null = 新对话）、切会话不串台、
/// 发送成功清草稿、clearAllDrafts 全清。
library;

import 'package:dshchat/ui/composer_drafts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerDraftStore 按会话隔离', () {
    setUp(composerDrafts.clearAllDrafts);
    tearDown(composerDrafts.clearAllDrafts);

    test('没有草稿的会话返回空草稿，不抛异常', () {
      final d = composerDrafts.draftOf('s1');
      expect(d.text, isEmpty);
      expect(d.images, isEmpty);
      expect(d.isEmpty, isTrue);
    });

    test('null 键（新对话）与有 id 会话互不串台', () {
      composerDrafts.setDraftText(null, '新对话里输入的');
      composerDrafts.setDraftText('s1', '会话一里输入的');

      expect(composerDrafts.draftOf(null).text, '新对话里输入的');
      expect(composerDrafts.draftOf('s1').text, '会话一里输入的');
    });

    test('切会话存取：旧会话草稿保留，新会话拿到自己的草稿', () {
      // 模拟切会话：先在 A 会话输入，切到 B，再切回 A。
      composerDrafts.setDraftText('A', 'A 的草稿');
      composerDrafts.setDraftText('B', 'B 的草稿');
      expect(composerDrafts.draftOf('A').text, 'A 的草稿');
      expect(composerDrafts.draftOf('B').text, 'B 的草稿');
    });

    test('图片随草稿按会话保存，列表整体覆盖不重复追加', () {
      final img = (
        path: '/a/b.png',
        name: 'b.png',
        mediaType: 'image/png',
        base64: 'BASE64',
      );
      composerDrafts.setDraftImages('s1', <ComposerDraftImage>[img]);
      composerDrafts.setDraftImages('s1', <ComposerDraftImage>[img]);

      final d = composerDrafts.draftOf('s1');
      expect(d.images, hasLength(1));
      expect(d.images.first, same(img));
      expect(composerDrafts.draftOf('s2').images, isEmpty);
    });

    test('发送成功后清掉该会话草稿，其他会话不受影响', () {
      composerDrafts.setDraftText('s1', '待发送');
      composerDrafts.setDraftText('s2', '别的会话的');

      composerDrafts.clearSentDraft('s1');

      expect(composerDrafts.draftOf('s1').text, isEmpty);
      expect(composerDrafts.draftOf('s2').text, '别的会话的');
    });

    test('clearDraft 清掉单个会话草稿，其他不受影响', () {
      composerDrafts.setDraftText('s1', '会话一');
      composerDrafts.setDraftText('s2', '会话二');

      composerDrafts.clearDraft('s1');

      expect(composerDrafts.draftOf('s1').text, '');
      expect(composerDrafts.draftOf('s2').text, '会话二');
    });

    test('clearAllDrafts 清空全部（含 null 键）', () {
      composerDrafts.setDraftText(null, '新对话');
      composerDrafts.setDraftText('s1', '会话一');

      composerDrafts.clearAllDrafts();

      expect(composerDrafts.draftOf(null).isEmpty, isTrue);
      expect(composerDrafts.draftOf('s1').isEmpty, isTrue);
    });
  });
}
