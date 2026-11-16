/**
 * Agent 预设模型 —— 对照 openapi §AgentPreset（GET /chat/agent-presets 的 items）。
 *
 * 字段：id/name（required）、description（可选）、trust: 'system'|'user'（required）、
 * isDefault/available: boolean（required）。解析沿用宽容口径（Models.ts D1）：
 * 姊妹仓实证旧桥 0.2.x 的 AgentPresetRow 不下发 trust，严格解码曾整份列表打挂，
 * 故缺键回默认值（trust 默认 'system'，available 默认 true，可渲染优先）。
 */

import { JsonAccess, JsonMap } from './JsonAccess';

export const AGENT_PRESET_TRUST_SYSTEM: string = 'system';
export const AGENT_PRESET_TRUST_USER: string = 'user';

export class AgentPreset {
  id: string = '';
  name: string = '';
  description: string | null = null;
  trust: string = AGENT_PRESET_TRUST_SYSTEM;
  isDefault: boolean = false;
  available: boolean = true;

  static fromJson(map: JsonMap | null): AgentPreset {
    const v: AgentPreset = new AgentPreset();
    v.id = JsonAccess.str(map, 'id') ?? '';
    v.name = JsonAccess.str(map, 'name') ?? '';
    v.description = JsonAccess.str(map, 'description');
    v.trust = JsonAccess.str(map, 'trust') ?? AGENT_PRESET_TRUST_SYSTEM;
    v.isDefault = JsonAccess.bool(map, 'isDefault') ?? false;
    v.available = JsonAccess.bool(map, 'available') ?? true;
    return v;
  }

  static listFrom(values: Object[]): AgentPreset[] {
    const out: AgentPreset[] = [];
    for (let i = 0; i < values.length; i++) {
      out.push(AgentPreset.fromJson(JsonAccess.asMap(values[i])));
    }
    return out;
  }

  /** round-trip 出站形状（协议口径：description 为 null 时省键）。 */
  toJson(): JsonMap {
    const m: JsonMap = {};
    m['id'] = this.id;
    m['name'] = this.name;
    if (this.description !== null) {
      m['description'] = this.description;
    }
    m['trust'] = this.trust;
    m['isDefault'] = this.isDefault;
    m['available'] = this.available;
    return m;
  }
}
