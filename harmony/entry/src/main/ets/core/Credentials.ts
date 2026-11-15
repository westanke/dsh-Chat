/**
 * bridge 凭证数据形状（鸿蒙版）—— 移植自安卓版 app/lib/bridge/credentials.dart
 * 的**纯数据部分**。支撑「一次配对，此后自动连接」：pair() 成功后 save()，
 * 下次启动 load() 命中则走 GatewayClient.connect()（子协议 dsh-auth）。
 *
 * 分层决策（PORT-MAP.md 决策 D2）：安卓版把 SharedPreferences（平台通道）和
 * 静态全局混在一个类里；鸿蒙版 core 只管「数据形状 + JSON 编解码」（本文件，
 * node 可直测），持久化用 ArkTS preferences 封装在 entry 层（CredentialsStore），
 * 状态注入 gateway，core 不持有全局可变状态。
 */

import { JsonAccess, JsonMap } from './JsonAccess';

/** 存储键名：值为 JSON {baseUrl, token}。 */
export const CREDENTIALS_STORAGE_KEY = 'dsh.credentials';

/** 配对凭证（baseUrl + token）。 */
export class DshCredentials {
  readonly baseUrl: string;
  readonly token: string;

  constructor(baseUrl: string, token: string) {
    this.baseUrl = baseUrl;
    this.token = token;
  }

  get isComplete(): boolean {
    return this.baseUrl.length > 0 && this.token.length > 0;
  }

  /** 解析存储的 JSON 文本；形状不符返回 null（调用方按未配对处理并清除）。 */
  static decode(raw: string): DshCredentials | null {
    const j = JsonAccess.asMap(JsonAccess.parse(raw));
    if (j === null) {
      return null;
    }
    const baseUrl = JsonAccess.str(j, 'baseUrl');
    const token = JsonAccess.str(j, 'token');
    if (baseUrl === null || token === null) {
      return null;
    }
    return new DshCredentials(baseUrl, token);
  }

  /** 编码为存储 JSON（字段齐全才有效，直接全量输出）。 */
  encode(): string {
    return JSON.stringify({ baseUrl: this.baseUrl, token: this.token });
  }
}
