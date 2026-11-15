/**
 * 宽容 JSON 取值助手 —— 鸿蒙 core 层唯一的 JSON 解析入口。
 *
 * 口径移植自姊妹仓 dsh-companion-harmony（1013 个 node 用例验证过的同源实现），
 * 对应安卓版 `fromJson` 的「尽力解析」但**更宽容**：
 * 缺键 / 显式 null / 类型不符 → 一律退化为默认值或 null，**绝不抛异常**。
 *
 * 为什么不用安卓版的「缺字段抛异常」：姊妹仓历史上因 `AgentPreset.trust` 缺键、
 * `PluginInventory.profile` 显式 null 等三次把整页数据打挂；协议文档里标 required
 * 的字段，旧版本桥实际可能不下发。宽容解析让界面始终有东西可渲染。
 *
 * ArkTS 写法约束（宪法 §7）：无 any/unknown（Object + as 收敛）、
 * 无结构化破坏性赋值（for 循环遍历）、不运行时改对象 shape。
 */
export type JsonMap = Record<string, Object>;

export class JsonAccess {
  /** 解析 JSON 文本，失败返回 null。 */
  static parse(text: string): Object | null {
    try {
      const value: Object = JSON.parse(text) as Object;
      return value;
    } catch (e) {
      return null;
    }
  }

  /** 把一个值收敛成可用于索引的键值对象；非对象返回 null。 */
  static asMap(value: Object | null | undefined): JsonMap | null {
    if (value === null || value === undefined) {
      return null;
    }
    if (typeof value !== 'object' || Array.isArray(value)) {
      return null; // 数组不是 JSON 对象（姊妹仓同口径）。
    }
    return value as JsonMap;
  }

  /** 取字段原始值；键不存在或为 null 时返回 null。 */
  static raw(map: JsonMap | null, key: string): Object | null {
    if (map === null) {
      return null;
    }
    if (!(key in map)) {
      return null;
    }
    const v: Object = map[key];
    if (v === undefined || v === null) {
      return null;
    }
    return v;
  }

  /** 取字符串字段；类型不符返回 null。 */
  static str(map: JsonMap | null, key: string): string | null {
    const v = JsonAccess.raw(map, key);
    return typeof v === 'string' ? v as string : null;
  }

  /** 取数字字段（含整型/浮点）；类型不符返回 null。 */
  static num(map: JsonMap | null, key: string): number | null {
    const v = JsonAccess.raw(map, key);
    return typeof v === 'number' ? v as number : null;
  }

  /** 取布尔字段；类型不符返回 null。 */
  static bool(map: JsonMap | null, key: string): boolean | null {
    const v = JsonAccess.raw(map, key);
    return typeof v === 'boolean' ? v as boolean : null;
  }

  /** 取数组字段；非数组返回空数组。 */
  static arr(map: JsonMap | null, key: string): Object[] {
    const v = JsonAccess.raw(map, key);
    return Array.isArray(v) ? v as Object[] : [];
  }

  /** 取子对象字段；非对象返回 null。 */
  /** 取对象数组；非对象项过滤掉，缺键/类型不符回空数组（姊妹仓同款）。 */
  static objArr(map: JsonMap | null, key: string): JsonMap[] {
    const raw: Object[] = JsonAccess.arr(map, key);
    const out: JsonMap[] = [];
    for (let i = 0; i < raw.length; i++) {
      const item: JsonMap | null = JsonAccess.asMap(raw[i]);
      if (item !== null) {
        out.push(item);
      }
    }
    return out;
  }

  static obj(map: JsonMap | null, key: string): JsonMap | null {
    return JsonAccess.asMap(JsonAccess.raw(map, key));
  }

  /** 取数字数组字段，过滤非数字项。 */
  static numArr(map: JsonMap | null, key: string): number[] {
    const out: number[] = [];
    const items = JsonAccess.arr(map, key);
    for (let i = 0; i < items.length; i++) {
      const it: Object = items[i];
      if (typeof it === 'number') {
        out.push(it as number);
      }
    }
    return out;
  }

  /** 取字符串数组字段，过滤非字符串项。 */
  static strArr(map: JsonMap | null, key: string): string[] {
    const out: string[] = [];
    const items = JsonAccess.arr(map, key);
    for (let i = 0; i < items.length; i++) {
      const it: Object = items[i];
      if (typeof it === 'string') {
        out.push(it as string);
      }
    }
    return out;
  }

  // ---- 便捷默认值版（内部仍走单一入口，调用点少一层 `??`）----

  /** 字符串字段 + 默认值。 */
  static strOr(map: JsonMap | null, key: string, fallback: string): string {
    const v = JsonAccess.str(map, key);
    return v === null ? fallback : v;
  }

  /** 数字字段 + 默认值。 */
  static numOr(map: JsonMap | null, key: string, fallback: number): number {
    const v = JsonAccess.num(map, key);
    return v === null ? fallback : v;
  }

  /** 布尔字段 + 默认值。 */
  static boolOr(map: JsonMap | null, key: string, fallback: boolean): boolean {
    const v = JsonAccess.bool(map, key);
    return v === null ? fallback : v;
  }
}
