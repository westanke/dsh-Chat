/**
 * 斜杠面板四条客户端功能命令的落点（/new /model /export /features）。
 *
 * 从 pages/ChatView.ets 抽出（该文件已超单文件行数纪律，新逻辑不再往里堆）：
 * ChatView 只负责把「模型弹层开关 / 设置页 / 当前标题」三个钩子交进来。
 * 这四条命令**本地执行，绝不上送服务端** —— 桥的 executeCommand 只认内核命令，
 * 发过去就是 404 COMMAND_NOT_FOUND（安卓 chat_page.dart 的 _runAppCommand 同口径）。
 */

import { ChatStore } from '../core/ChatStore';
import { ChatMessage } from '../core/HistoryPage';
import { sessionMarkdownOf } from '../core/SessionExport';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

/** 提示条停留时长（与 ArtifactCard 同一档，鸿蒙开发台 R017 认 1500ms 档）。 */
const TOAST_MS: number = 1500;

/** ChatView 侧要提供的三个落点。 */
export interface AppCommandHooks {
  /** /model：打开模型弹层（无会话时不该开，钩子内部自己判）。 */
  openModel: () => void;
  /** /features：跳设置页（Index 的 onOpenSettings 回调）。 */
  openSettings: () => void;
  /** /export：导出标题（当前会话标题，缺省「未命名会话」）。 */
  titleOf: () => string;
}

/** ChatView 侧的宿主：store 可空（还没连上时命令一律空转）。 */
export interface AppCommandHost {
  store: ChatStore | null;
  hooks: AppCommandHooks;
}

/**
 * ChatView 的 onAppCommand 薄封装（把「store 可空」这一层判断从页面里搬出来，
 * 页面只留一行调用）。store 为空说明还没连上，命令直接空转。
 */
export function onAppCommandOf(host: AppCommandHost, name: string): void {
  const st: ChatStore | null = host.store;
  if (st === null) {
    return;
  }
  runAppCommandOn(st, name, host.hooks);
}

/** 执行一条客户端功能命令；不认识的命令名直接忽略。 */
export function runAppCommandOn(store: ChatStore, name: string, hooks: AppCommandHooks): void {
  if (name === 'new') {
    store.newChat();
    return;
  }
  if (name === 'model') {
    hooks.openModel();
    return;
  }
  if (name === 'export') {
    copySessionMarkdown(store.messages, hooks.titleOf());
    return;
  }
  if (name === 'features') {
    hooks.openSettings();
  }
}

/** 会话 Markdown 落剪贴板（鸿蒙没有「下载」目录直写口径，先复制再让用户粘贴保存）。 */
export function copySessionMarkdown(messages: ChatMessage[], title: string): void {
  const md: string = sessionMarkdownOf(messages, title);
  if (md.length === 0) {
    promptAction.showToast({ message: '这个会话还没有可导出的内容', duration: TOAST_MS });
    return;
  }
  const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, md);
  pasteboard.getSystemPasteboard().setData(data).then((): void => {
    promptAction.showToast({ message: '已复制会话 Markdown', duration: TOAST_MS });
  }).catch((): void => {
    promptAction.showToast({ message: '复制失败', duration: TOAST_MS });
  });
}
