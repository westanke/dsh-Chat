/**
 * 会话页展示纯函数 —— 从 ChatStore 拆出（500 行纪律，2026-11-16）。
 * 全部无状态、node 直测；ChatStore getter 一行转发。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { DshSession } from './Models';
import { GatewayState } from './GatewayEvents';

/** 当前会话标题（顶栏居中显示；新对话空串）。 */
export function sessionTitleOf(sessions: DshSession[], sessionId: string | null): string {
  if (sessionId === null || sessionId === '') {
    return '';
  }
  for (const s of sessions) {
    if (s.id === sessionId) {
      return s.displayTitle;
    }
  }
  return '';
}

/** 设备名（hello.device.name 优先，兜底 DSH Bridge）。 */
export function deviceLabelOf(device: JsonMap | null): string {
  if (device !== null) {
    const name: string = JsonAccess.strOr(device, 'name', '').trim();
    if (name !== '') {
      return name;
    }
  }
  return 'DSH Bridge';
}

/** 连接地址（去协议前缀与尾斜杠，只留 host[:port]）。 */
export function connectionLabelOf(baseUrl: string): string {
  const stripped: string = baseUrl.replace(/^https?:\/\//, '').replace(/\/+$/, '');
  return stripped === '' ? baseUrl : stripped;
}

/** 连接状态中文（设置页连接区）。 */
export function stateLabelOf(state: GatewayState): string {
  if (state === GatewayState.READY) {
    return '已连接';
  }
  if (state === GatewayState.CONNECTING) {
    return '连接中';
  }
  if (state === GatewayState.CLOSED) {
    return '已断开';
  }
  if (state === GatewayState.AUTH_FAILED) {
    return '鉴权失败';
  }
  return '未连接';
}
