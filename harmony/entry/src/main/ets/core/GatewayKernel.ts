/**
 * 通用内核调用面的收发（dshrb-v1）—— 从 GatewayClient 拆出控行数。
 *
 * 参数统一收 GatewayClient（同 GatewayRequests.ts 范式）。协议事实来源与错误码
 * 见 core/KernelCall.ts 文件头；这里只做「发帧 / 登记 / 结算 / 超时」。
 */

import { JsonMap } from './JsonAccess';
import { KernelCallResult, KernelEndpoint, KernelPending, KERNEL_CALL_TIMEOUT_MS, KERNEL_SESSION_SEARCH } from './KernelCall';
import { sessionSearchArgs } from './SessionSearch';
import { RequestException } from './GatewayEvents';
import type { GatewayClient } from './GatewayClient';

/** 目录里的一条（没有返回 null）。 */
export function kernelEndpointOf(client: GatewayClient, name: string): KernelEndpoint | null {
  for (let i = 0; i < client.kernel.catalog.length; i++) {
    if (client.kernel.catalog[i].endpoint === name) {
      return client.kernel.catalog[i];
    }
  }
  return null;
}

/** 会话内容搜索是否可用（dshrb 协商成功 + 目录里有 session/search）。 */
export function kernelSearchSupportedOn(client: GatewayClient): boolean {
  return kernelEndpointOf(client, KERNEL_SESSION_SEARCH) !== null;
}

/** 收到 kernel-call-result：按 callId 结算；已取消/已超时的直接丢弃（幂等回放也靠它）。 */
export function settleKernelCallOn(client: GatewayClient, result: KernelCallResult): void {
  const p: KernelPending | null = client.kernel.registry.take(result.callId);
  if (p === null) {
    return;
  }
  client.deps.timers.cancel(p.timer);
  p.resolve(result);
}

/** 发起一次内核调用（callId 自动生成；写操作重试请用 kernelCallWithIdOn 复用 id）。 */
export function kernelCallOn(client: GatewayClient, endpoint: string, args: JsonMap,
                             timeoutMs: number = KERNEL_CALL_TIMEOUT_MS): Promise<KernelCallResult> {
  client.kernel.seq += 1;
  const callId: string = 'k' + client.kernel.seq.toString() + '-' + client.nowMs().toString();
  return kernelCallWithIdOn(client, callId, endpoint, args, timeoutMs);
}

/** 指定 callId 的内核调用（桥按 principal+callId 24h 幂等）。 */
export function kernelCallWithIdOn(client: GatewayClient, callId: string, endpoint: string,
                                   args: JsonMap, timeoutMs: number = KERNEL_CALL_TIMEOUT_MS): Promise<KernelCallResult> {
  return new Promise<KernelCallResult>((resolve: (r: KernelCallResult) => void,
                                        reject: (e: Error) => void) => {
    if (client.handle === null) {
      reject(new RequestException('NOT_CONNECTED', '连接未就绪'));
      return;
    }
    const self: GatewayClient = client;
    const timer: number = client.deps.timers.schedule(timeoutMs, (): void => {
      const p: KernelPending | null = self.kernel.registry.take(callId);
      if (p !== null) {
        p.reject(new RequestException('call/timeout', '内核调用超时'));
      }
    });
    const pending: KernelPending = new KernelPending(resolve, reject, timer);
    if (!client.kernel.registry.add(callId, pending)) {
      client.deps.timers.cancel(timer);
      reject(new RequestException('call/in-flight', '同一 callId 已在执行'));
      return;
    }
    const frame: JsonMap = { type: 'kernel-call', callId: callId, endpoint: endpoint, args: args };
    try {
      client.handle.send(JSON.stringify(frame));
    } catch (e) {
      const p: KernelPending | null = client.kernel.registry.take(callId);
      if (p !== null) {
        client.deps.timers.cancel(p.timer);
        p.reject(new RequestException('NOT_CONNECTED', '发送失败'));
      }
    }
  });
}

/** 尽力取消（只发帧；结果帧晚到按 callId 去重丢弃）。 */
export function kernelCancelOn(client: GatewayClient, callId: string): boolean {
  if (client.handle === null || callId === '') {
    return false;
  }
  const frame: JsonMap = { type: 'kernel-call-cancel', callId: callId };
  try {
    client.handle.send(JSON.stringify(frame));
    return true;
  } catch (e) {
    return false;
  }
}

/** 会话内容搜索（端点/参数键都按目录走；不可用时 NOT_SUPPORTED）。 */
export function searchSessionsOn(client: GatewayClient, query: string): Promise<KernelCallResult> {
  const ep: KernelEndpoint | null = kernelEndpointOf(client, KERNEL_SESSION_SEARCH);
  if (ep === null) {
    return Promise.reject(new RequestException('NOT_SUPPORTED', '内核搜索不可用'));
  }
  return kernelCallOn(client, ep.endpoint, sessionSearchArgs(ep, query));
}
