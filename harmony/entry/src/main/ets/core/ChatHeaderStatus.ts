/**
 * 顶栏状态行（安卓 app/lib/ui/chat_header_status.dart 口径）。
 *
 * 优先级（命中即返回）：未连接 > 连接中 > 已断开（含鉴权失败）> 等待审批 >
 * 等待回答 > 生成中 > 已连接（显示主机名）。「等待」压过「生成中」是官方口径：
 * 挂起项在等用户，比后台生成更需要被看见。
 *
 * 纯逻辑，node 直测。
 */

import { GatewayState } from './GatewayEvents';

export const HEADER_TONE_IDLE: string = 'idle';
export const HEADER_TONE_BUSY: string = 'busy';
export const HEADER_TONE_WARN: string = 'warn';
export const HEADER_TONE_ERROR: string = 'error';
export const HEADER_TONE_OK: string = 'ok';

/** 顶栏状态（扁平类；dot 颜色由 UI 按 tone 取 token）。 */
export class ChatHeaderStatus {
  tone: string = HEADER_TONE_IDLE;
  label: string = '未连接';

  constructor(tone: string, label: string) {
    this.tone = tone;
    this.label = label;
  }
}

export function chatHeaderStatus(state: GatewayState, streaming: boolean,
  waitingApproval: boolean, waitingAnswer: boolean, hostLabel: string): ChatHeaderStatus {
  if (state === GatewayState.IDLE) {
    return new ChatHeaderStatus(HEADER_TONE_IDLE, '未连接');
  }
  if (state === GatewayState.CONNECTING) {
    return new ChatHeaderStatus(HEADER_TONE_BUSY, '连接中');
  }
  if (state === GatewayState.CLOSED || state === GatewayState.AUTH_FAILED) {
    return new ChatHeaderStatus(HEADER_TONE_ERROR, '已断开');
  }
  if (waitingApproval) {
    return new ChatHeaderStatus(HEADER_TONE_WARN, '等待审批');
  }
  if (waitingAnswer) {
    return new ChatHeaderStatus(HEADER_TONE_WARN, '等待回答');
  }
  if (streaming) {
    return new ChatHeaderStatus(HEADER_TONE_BUSY, '生成中');
  }
  const host: string = hostLabel.trim();
  return new ChatHeaderStatus(HEADER_TONE_OK, host === '' ? '已连接' : host);
}
