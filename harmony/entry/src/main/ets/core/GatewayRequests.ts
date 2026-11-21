/**
 * Gateway 帧收发 —— 从 GatewayClient 拆出（宪法 §7 单文件 ≤500 行）。
 *
 * 三件事：发起请求并等回显、订阅会话事件流、把服务端帧分派到对应结算器/监听器。
 * 参数统一收 GatewayClient（同包循环引用走 import type，字段按需 public ——
 * 与 core/ChatActions.ts、core/ChatHitl.ts 同范式）。
 *
 * 协议口径（对齐 app/lib/bridge/gateway.dart 与 bridge 仓 ws-protocol.ts）：
 * - 客户端帧带 `type`，服务端回显帧带 `kind`（别混）；
 * - requestId 双兜底：优先 `data.requestId`，退回顶层 `requestId`；
 * - `subscribe` 的响应不回显 requestId（服务端排除表），发出即成功，不登记 pending；
 * - `ping` 由客户端发、服务端回 `pong`；服务端也可能发 `ping` 过来，要回 `pong`。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { WireBuilder } from './Wire';
import {
  GatewayEvent, GatewayState, RequestException, requestExceptionFromFrame, eventFromFrame,
} from './GatewayEvents';
import { REQUEST_TIMEOUT_MS } from './Transport';
import { KernelCallResult, parseKernelEndpoints } from './KernelCall';
import { settleKernelCallOn } from './GatewayKernel';
import type { GatewayClient, PendingRequest } from './GatewayClient';

/** 发起一次请求并等待回显（error 帧或超时 reject 稳定错误码）。 */
export function requestWithTimeoutOn(client: GatewayClient, type: string, payload: JsonMap | null,
                                    timeoutMs: number): Promise<JsonMap> {
  return new Promise<JsonMap>((resolve: (d: JsonMap) => void, reject: (e: Error) => void) => {
    const self: GatewayClient = client;
    self.requestSeq += 1;
    const requestId: string = 'r' + self.requestSeq.toString() + '-' + timeoutMs.toString();

    let settled: boolean = false;
    const ok = (data: JsonMap): void => {
      if (settled) {
        return;
      }
      settled = true;
      self.deps.timers.cancel(timer);
      self.pending.delete(requestId);
      resolve(data);
    };
    const fail = (err: Error): void => {
      if (settled) {
        return;
      }
      settled = true;
      self.deps.timers.cancel(timer);
      self.pending.delete(requestId);
      reject(err);
    };
    const timer: number = self.deps.timers.schedule(timeoutMs, (): void => {
      fail(new RequestException('TIMEOUT', '请求超时: ' + type));
    });

    if (self.handle === null) {
      fail(new RequestException('NOT_CONNECTED', '连接未就绪'));
      return;
    }
    const pr: PendingRequest = { resolve: ok, reject: fail, timer: timer };
    self.pending.set(requestId, pr);

    const b: WireBuilder = new WireBuilder();
    b.put('type', type);
    if (payload !== null) {
      const keys: string[] = Object.keys(payload);
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        if (k === 'type' || k === 'requestId') {
          continue;
        }
        b.put(k, JsonAccess.raw(payload, k));
      }
    }
    b.put('requestId', requestId);
    self.handle.send(JSON.stringify(b.buildMap()));
  });
}

/** 默认 30s 超时的请求。 */
export function requestOn(client: GatewayClient, type: string, payload: JsonMap | null): Promise<JsonMap> {
  return requestWithTimeoutOn(client, type, payload, REQUEST_TIMEOUT_MS);
}

/**
 * 订阅会话事件流。subscribe 帧的响应不回显 requestId（服务端排除表），
 * 所以不登记 pending，发出即成功。
 */
export function subscribeOn(client: GatewayClient, sessionId: string): boolean {
  if (client.handle === null) {
    return false;
  }
  const b: WireBuilder = new WireBuilder();
  b.put('type', 'subscribe');
  b.put('sessionId', sessionId);
  client.handle.send(JSON.stringify(b.buildMap()));
  return true;
}

/**
 * 收帧并分派。返回值表达「已消费」，便于单测断言；
 * 未识别的 kind 且无 requestId 时静默丢弃（服务端可能新增帧类型）。
 */
export function onFrameOn(client: GatewayClient, text: string,
                         emit: (event: GatewayEvent) => void,
                         onHello: (data: JsonMap | null, requestId: string) => void): void {
  const frame: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(text));
  if (frame === null) {
    return;
  }
  const kind: string = JsonAccess.strOr(frame, 'kind', '');
  // dshrb-v1 两帧**不带 data 包裹**，必须在取 data 之前分派。
  if (kind === 'kernel-endpoints') {
    const endpoints = parseKernelEndpoints(frame);
    client.kernel.catalog = endpoints;
    client.traceMsg('[gw] kernel endpoints=' + endpoints.length.toString());
    emit(GatewayEvent.kernelCatalog(endpoints));
    return;
  }
  if (kind === 'kernel-call-result') {
    settleKernelCallOn(client, KernelCallResult.fromFrame(frame));
    return;
  }
  const data: JsonMap | null = JsonAccess.asMap(JsonAccess.raw(frame, 'data'));
  // 双兜底：requestId 可能在 data 里，也可能在顶层。
  let requestId: string = '';
  if (data !== null) {
    requestId = JsonAccess.strOr(data, 'requestId', '');
  }
  if (requestId === '') {
    requestId = JsonAccess.strOr(frame, 'requestId', '');
  }

  if (kind === 'hello') {
    onHello(data, requestId);
    return;
  }
  if (kind === 'paired') {
    return; // 鸿蒙配对走 REST，配对帧不出现；出现也忽略。
  }
  if (kind === 'pong') {
    return;
  }
  if (kind === 'ping') {
    if (client.handle !== null) {
      const b: WireBuilder = new WireBuilder();
      b.put('type', 'pong');
      client.handle.send(JSON.stringify(b.buildMap()));
    }
    return;
  }
  if (kind === 'event') {
    const ev: GatewayEvent | null = eventFromFrame(data);
    if (ev !== null) {
      emit(ev);
    }
    return;
  }
  if (kind === 'connection-resync-required') {
    const dropped: boolean = data !== null && JsonAccess.boolOr(data, 'dropped', false);
    emit(GatewayEvent.resync(dropped));
    return;
  }
  if (kind === 'error') {
    const err: RequestException = requestExceptionFromFrame(data);
    const p: PendingRequest | undefined = requestId !== '' ? client.pending.get(requestId) : undefined;
    if (p !== undefined) {
      client.pending.delete(requestId);
      p.reject(err);
    }
    return;
  }
  // 默认：带 requestId 的回显帧 → 结算对应请求。
  const p: PendingRequest | undefined = requestId !== '' ? client.pending.get(requestId) : undefined;
  if (p !== undefined) {
    client.pending.delete(requestId);
    const empty: JsonMap = {};
    p.resolve(data !== null ? data : empty);
  }
}
