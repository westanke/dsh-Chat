/**
 * dshrb-v1 内核调用面的连接级状态（目录 + 在飞登记表 + callId 序号）。
 *
 * 单独一个类是为了让 GatewayClient 守住宪法 §7 的 500 行上限：客户端只持有一个
 * `kernel` 字段，行为在 core/GatewayKernel.ts 的纯函数里（收 client 的范式与
 * GatewayRequests.ts 一致）。
 */

import { KernelCallRegistry, KernelEndpoint } from './KernelCall';

export class KernelPlane {
  /** hello 后由服务端推的端点目录；重连先清空、整帧替换。 */
  catalog: KernelEndpoint[] = [];
  /** 在飞调用（callId 配对）。 */
  registry: KernelCallRegistry = new KernelCallRegistry();
  /** 客户端自铸 callId 的序号。 */
  seq: number = 0;
}
