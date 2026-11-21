/**
 * 通用内核调用面（bridge `dshrb-v1` 子协议，issue #26 阶段 5）。
 *
 * 协议事实来源：`dsh-remote-bridge` 的 `docs/api/asyncapi.yaml`（Kernel-call
 * plane）与 `docs/project/API.md` §866-1007、安卓实现 `app/lib/bridge/gateway_kernel.dart`。
 *
 * 四个帧只在客户端声明的子协议清单里有 `dshrb-v1` 时才存在：
 * - C→S `{type:'kernel-call', callId, endpoint, args?}`；
 * - C→S `{type:'kernel-call-cancel', callId}`；
 * - S→C `{kind:'kernel-endpoints', endpoints:[{endpoint,scope,stream,wires,summary}]}`
 *   （握手后立即推、整帧替换；元素形状未冻结，未知字段忽略）；
 * - S→C `{kind:'kernel-call-result', callId, ok, value?, error?{code,message}}`
 *   （**不带 data.requestId**，按 callId 配对）。
 *
 * 纯逻辑，不 import 任何 @kit；请求登记表与解析都能 node 直测。
 */

import { JsonAccess, JsonMap } from './JsonAccess';

/** 客户端等待内核结果的超时（服务端硬上限 30s，客户端留 5s 余量）。 */
export const KERNEL_CALL_TIMEOUT_MS: number = 35000;

/** 会话内容搜索的内核端点名（白名单里的那条）。 */
export const KERNEL_SESSION_SEARCH: string = 'session/search';

/** `kernel-endpoints` 里的一条：能调什么、要什么 scope、接受哪些 wire 键。 */
export class KernelEndpoint {
  endpoint: string = '';
  scope: string = '';
  summary: string = '';
  /** 流式端点：桥把结果收进 `{frames, truncated?}` 一次性返回。 */
  stream: boolean = false;
  /** 该端点接受的 wire 键集合（strict codec 既拒缺键也拒多键）。 */
  wires: string[] = [];

  static fromJson(value: JsonMap | null): KernelEndpoint | null {
    if (value === null) {
      return null;
    }
    const endpoint: string = JsonAccess.strOr(value, 'endpoint', '');
    if (endpoint === '') {
      return null; // 无端点名的条目跳过（元素形状未冻结，容忍脏条目）。
    }
    const out: KernelEndpoint = new KernelEndpoint();
    out.endpoint = endpoint;
    out.scope = JsonAccess.strOr(value, 'scope', '');
    out.summary = JsonAccess.strOr(value, 'summary', '');
    out.stream = JsonAccess.boolOr(value, 'stream', false);
    const raw: Object[] = JsonAccess.arr(value, 'wires');
    for (let i = 0; i < raw.length; i++) {
      const w: Object = raw[i];
      if (typeof w === 'string') {
        out.wires.push(w as string);
      }
    }
    return out;
  }

  /** 该端点是否接受这个 wire 键。 */
  accepts(wire: string): boolean {
    return this.wires.indexOf(wire) >= 0;
  }
}

/**
 * 解析 `kernel-endpoints` 帧。
 *
 * 桥实际发的是 `{kind:'kernel-endpoints', data:{endpoints:[...]}}`（ws-kernel-call.ts
 * `announce()`，2026-11-21 真机日志 `kernel endpoints=0` 实证）；docs 里写的「顶层
 * endpoints」是旧口径。这里先读 `data`，读不到再回退顶层，兼容两种形状。
 * 目录是唯一真相：客户端不许硬编码端点表，也不把它当授权表（scope 仍可能拒）。
 */
export function parseKernelEndpoints(frame: JsonMap | null): KernelEndpoint[] {
  if (frame === null) {
    return [];
  }
  const payload: JsonMap = JsonAccess.obj(frame, 'data') ?? frame;
  const raw: JsonMap[] = JsonAccess.objArr(payload, 'endpoints');
  const out: KernelEndpoint[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item: KernelEndpoint | null = KernelEndpoint.fromJson(raw[i]);
    if (item !== null) {
      out.push(item);
    }
  }
  return out;
}

/** `kernel-call-result` 的内容：成功带 value，失败带 error{code,message}。 */
export class KernelCallResult {
  callId: string = '';
  ok: boolean = false;
  /** 端点自定义结果，形状不做保证；流式端点固定为 `{frames, truncated?}`。 */
  value: Object | null = null;
  errorCode: string = '';
  errorMessage: string = '';

  static fromFrame(frame: JsonMap | null): KernelCallResult {
    const out: KernelCallResult = new KernelCallResult();
    if (frame === null) {
      return out;
    }
    // 桥形状：{kind, data:{callId, ok, value|error}}；兼容无 data 的旧读法。
    const payload: JsonMap = JsonAccess.obj(frame, 'data') ?? frame;
    out.callId = JsonAccess.strOr(payload, 'callId', '');
    out.ok = JsonAccess.boolOr(payload, 'ok', false);
    out.value = JsonAccess.raw(payload, 'value');
    const error: JsonMap | null = JsonAccess.obj(payload, 'error');
    if (error !== null) {
      out.errorCode = JsonAccess.strOr(error, 'code', '');
      out.errorMessage = JsonAccess.strOr(error, 'message', '');
    }
    return out;
  }

  /** 成功且 value 是对象。 */
  object(): JsonMap | null {
    return this.ok ? JsonAccess.asMap(this.value) : null;
  }

  /** 流式端点的帧数组（`value.frames`）。 */
  frames(): Object[] {
    const map: JsonMap | null = this.object();
    return map === null ? [] : JsonAccess.arr(map, 'frames');
  }

  /** 失败时给用户看的一句话。 */
  message(): string {
    if (this.ok) {
      return '';
    }
    if (this.errorMessage !== '') {
      return this.errorMessage;
    }
    return this.errorCode === '' ? '内核调用失败' : this.errorCode;
  }
}

/** 一次在飞调用（callId → 结算器 + 超时定时器）。 */
export class KernelPending {
  resolve: (r: KernelCallResult) => void;
  reject: (e: Error) => void;
  timer: number;

  constructor(resolve: (r: KernelCallResult) => void, reject: (e: Error) => void, timer: number) {
    this.resolve = resolve;
    this.reject = reject;
    this.timer = timer;
  }
}

/**
 * 在飞调用登记表。与经典请求的 pending（requestId 配对）分开：调用可取消、
 * 可幂等重放，两套 id 语义不同。
 */
export class KernelCallRegistry {
  private inflight: Map<string, KernelPending> = new Map<string, KernelPending>();

  length(): number {
    return this.inflight.size;
  }

  contains(callId: string): boolean {
    return this.inflight.has(callId);
  }

  /** 登记一次调用；同 id 已存在返回 false（调用方应先判 in-flight）。 */
  add(callId: string, pending: KernelPending): boolean {
    if (this.inflight.has(callId)) {
      return false;
    }
    this.inflight.set(callId, pending);
    return true;
  }

  /** 取出并摘除；已摘除的不会被二次结算（晚到结果直接丢弃）。 */
  take(callId: string): KernelPending | null {
    if (callId === '') {
      return null;
    }
    const p: KernelPending | undefined = this.inflight.get(callId);
    if (p === undefined) {
      return null;
    }
    this.inflight.delete(callId);
    return p;
  }

  /** 断连/释放：全部 reject（不再等结果帧）。 */
  failAll(reason: string): void {
    const keys: string[] = [];
    this.inflight.forEach((_v: KernelPending, k: string): void => {
      keys.push(k);
    });
    for (let i = 0; i < keys.length; i++) {
      const p: KernelPending | null = this.take(keys[i]);
      if (p !== null) {
        p.reject(new Error(reason));
      }
    }
  }
}
