/**
 * 会话导出为 Markdown —— 对照安卓 `app/lib/ui/chat_overflow_menu.dart` 的
 * `sessionMarkdown(state)`（/export 客户端功能命令与溢出菜单「导出」共用）。
 *
 * 口径：
 * - 只导用户与助手的正文；过程组（process）→ 「本轮过程」折叠内容不导，
 *   错误行、命令回显（role='command'）、文件卡（role='files'）也不导 ——
 *   它们是界面装饰，进 Markdown 只会变成噪音；
 * - 标题取会话 displayTitle，没有就「未命名会话」；
 * - 正文里已有的行首 `#` 不再转义（聊天记录本来就可能带 Markdown）。
 *
 * 纯逻辑，node 直测。
 */

import { ChatMessage } from './HistoryPage';

/** 会话 Markdown 标题（安卓同款兜底文案）。 */
export function exportTitleOf(sessions: string[], currentId: string): string {
  for (let i = 0; i < sessions.length; i++) {
    if (sessions[i].length > 0) {
      return sessions[i];
    }
  }
  return currentId.length > 0 ? currentId : '未命名会话';
}

/** 消息 → Markdown 正文（空会话返回空串，调用方据此提示而不是导出空文件）。 */
export function sessionMarkdownOf(messages: ChatMessage[], title: string): string {
  const parts: string[] = [];
  parts.push('# ' + title);
  parts.push('');
  for (let i = 0; i < messages.length; i++) {
    const m: ChatMessage = messages[i];
    if (m.role !== 'user' && m.role !== 'assistant') {
      continue;
    }
    const body: string = m.text.trim();
    if (body.length === 0) {
      continue;
    }
    parts.push(m.role === 'user' ? '## 用户' : '## 助手');
    parts.push('');
    parts.push(body);
    parts.push('');
  }
  return parts.length > 2 ? parts.join('\n') : '';
}
