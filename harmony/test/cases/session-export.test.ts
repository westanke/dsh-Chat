/**
 * 会话导出 Markdown 测试 —— 对应安卓 chat_overflow_menu.dart 的 sessionMarkdown。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { sessionMarkdownOf, exportTitleOf } from '../../entry/src/main/ets/core/SessionExport.ts';

function msg(role: string, text: string): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = role;
  m.text = text;
  return m;
}

test('sessionMarkdownOf: 只导用户与助手正文，跳过过程组/错误/命令回显/文件卡', () => {
  const md = sessionMarkdownOf([
    msg('user', '你好'),
    msg('process', '调用了工具'),
    msg('assistant', '有什么可以帮你'),
    msg('error', '出错了'),
    msg('command', '/stats'),
    msg('files', 'a.txt'),
  ], '测试会话');
  assert.equal(md, '# 测试会话\n\n## 用户\n\n你好\n\n## 助手\n\n有什么可以帮你\n');
});

test('sessionMarkdownOf: 空正文与全空白会话返回空串', () => {
  assert.equal(sessionMarkdownOf([], 'x'), '');
  assert.equal(sessionMarkdownOf([msg('user', '   ')], 'x'), '');
});

test('sessionMarkdownOf: 正文首尾空白剥掉，内部换行保留', () => {
  const md = sessionMarkdownOf([msg('assistant', '\n第一行\n第二行\n')], 't');
  assert.equal(md, '# t\n\n## 助手\n\n第一行\n第二行\n');
});

test('exportTitleOf: 有标题用标题，没标题回落到会话 id / 未命名', () => {
  assert.equal(exportTitleOf(['会话 A'], 's-1'), '会话 A');
  assert.equal(exportTitleOf([], 's-1'), 's-1');
  assert.equal(exportTitleOf([''], ''), '未命名会话');
});
