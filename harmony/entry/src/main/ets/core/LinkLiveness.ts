/**
 * 连接活性判据 —— 从 GatewayClient 拆出（宪法 §7 单文件 ≤500 行）。
 *
 * 姊妹仓踩过的坑（companion PITFALLS「WS 半死：socket 断了但状态还写着已连接」）：
 * 断线通知要等对端发话或 TCP 超时，App 进后台被冻结时那条连接既没关也没人写，
 * 状态会停在「已连接」，之后每一帧都写进死连接、等满 30s 超时才失败。
 *
 * 判据必须是**最近一次收到入站帧的时刻**（坏帧也算活着），不是「最近一次状态迁移」；
 * 哨兵不用 0（真机时钟 `Date.now()` 与单测假钟从 0 起步会撞），用 `NO_INBOUND_YET`。
 */

import { LINK_LIVENESS_MS, NO_INBOUND_YET } from './Transport';

export class LinkLiveness {
  private lastInboundAt: number = NO_INBOUND_YET;

  /** 新连接建立时重置（hello 之前的静默不算死，那条路由 hello 超时管）。 */
  reset(): void {
    this.lastInboundAt = NO_INBOUND_YET;
  }

  /** 收到任意入站帧时调用（解析之前）。 */
  seen(nowMs: number): void {
    this.lastInboundAt = nowMs;
  }

  /** 静默超过上限即半死；还没收到过帧 → 不算死。 */
  isStale(nowMs: number): boolean {
    if (this.lastInboundAt === NO_INBOUND_YET) {
      return false;
    }
    return nowMs - this.lastInboundAt > LINK_LIVENESS_MS;
  }

  /** 距今静默毫秒数（没收到过帧回 -1，诊断/日志用）。 */
  silentFor(nowMs: number): number {
    return this.lastInboundAt === NO_INBOUND_YET ? -1 : nowMs - this.lastInboundAt;
  }
}
