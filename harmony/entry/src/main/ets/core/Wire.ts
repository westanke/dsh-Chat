/**
 * 请求体 JSON 拼装助手 —— 与姊妹仓 dsh-companion-harmony ModelsWire.ts 同源。
 *
 * 面向「出站」请求体的三条规矩之一（见 Models.ts 文件头）：
 * **null 一律省略**（encodeDefaults=false 语义）。入站解码一律走 JsonAccess，
 * 本类只管编码侧。
 *
 * ArkTS 口径：`JsonMap` 动态键写入是姊妹仓验证过的编译兼容写法
 * （`this.map[key] = value`）；不用 `Partial`/可选属性/运行时改 shape。
 */
import { JsonMap } from './JsonAccess';

export class WireBuilder {
  private map: JsonMap = {};

  /** 非 null 才写入；null 表示「不指定该字段」。 */
  put(key: string, value: Object | null): WireBuilder {
    if (value !== null) {
      this.map[key] = value;
    }
    return this;
  }

  /** 条件写入：仅在 flag 为 true 时写。 */
  putIf(flag: boolean, key: string, value: Object | null): WireBuilder {
    return flag ? this.put(key, value) : this;
  }

  /** 非 null 且非空串才写入（空串视为「未填」）。 */
  putNonBlank(key: string, value: string | null): WireBuilder {
    return value !== null && value.length > 0 ? this.put(key, value) : this;
  }

  buildMap(): JsonMap {
    return this.map;
  }

  build(): string {
    return JSON.stringify(this.map);
  }
}
