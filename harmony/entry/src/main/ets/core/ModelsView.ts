/**
 * 会话模型视图（models 应答收敛）—— 移植 app/lib/bridge/models_view.dart。
 *
 * 应答形状（ws-models.ts:58，chat-adapter.ts:160-184）：
 * `{sessionId, current:{provider,model,reasoningEffort?}, routable,
 *   groups:[{id,name,models:[{id,name,description?,contextWindow?,maxTokens?,
 *   reasoning?:{efforts:[{id,name,description?}], defaultEffort?}}]}],
 *   failures:[{provider,message}]}`
 * **没有 providers/modelCatalog 字段——groups 就是按 provider 分的组**。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { WireBuilder } from './Wire';

export class ModelReasoningEffort {
  id: string = '';
  name: string = '';

  static fromJson(j: JsonMap | null): ModelReasoningEffort {
    const m: ModelReasoningEffort = new ModelReasoningEffort();
    if (j === null) {
      return m;
    }
    m.id = JsonAccess.strOr(j, 'id', '');
    m.name = JsonAccess.strOr(j, 'name', m.id);
    return m;
  }

  static listFrom(map: JsonMap | null, key: string): ModelReasoningEffort[] {
    const out: ModelReasoningEffort[] = [];
    if (map === null) {
      return out;
    }
    const arr: Object[] = JsonAccess.arr(map, key);
    for (const item of arr) {
      const m: JsonMap | null = JsonAccess.asMap(item);
      if (m !== null) {
        out.push(ModelReasoningEffort.fromJson(m));
      }
    }
    return out;
  }
}

export class ModelReasoning {
  efforts: ModelReasoningEffort[] = [];
  defaultEffort: string | null = null;

  static fromJson(j: JsonMap | null): ModelReasoning {
    const r: ModelReasoning = new ModelReasoning();
    if (j === null) {
      return r;
    }
    r.efforts = ModelReasoningEffort.listFrom(j, 'efforts');
    r.defaultEffort = JsonAccess.str(j, 'defaultEffort');
    return r;
  }
}

export class ModelView {
  id: string = '';
  name: string = '';
  description: string | null = null;
  reasoning: ModelReasoning | null = null;

  static fromJson(j: JsonMap | null): ModelView {
    const v: ModelView = new ModelView();
    if (j === null) {
      return v;
    }
    v.id = JsonAccess.strOr(j, 'id', '');
    v.name = JsonAccess.strOr(j, 'name', v.id);
    v.description = JsonAccess.str(j, 'description');
    v.reasoning = ModelReasoning.fromJson(JsonAccess.obj(j, 'reasoning'));
    return v;
  }

  toMap(): JsonMap {
    const b: WireBuilder = new WireBuilder();
    b.put('id', this.id);
    b.put('name', this.name);
    b.putIf(this.description !== null, 'description', this.description as Object | null);
    if (this.reasoning !== null) {
      const efforts: Object[] = [];
      for (const e of this.reasoning.efforts) {
        const eb: WireBuilder = new WireBuilder();
        eb.put('id', e.id);
        eb.put('name', e.name);
        efforts.push(eb.buildMap());
      }
      const rb: WireBuilder = new WireBuilder();
      rb.put('efforts', efforts);
      rb.putIf(this.reasoning.defaultEffort !== null, 'defaultEffort',
        this.reasoning.defaultEffort as Object | null);
      b.put('reasoning', rb.buildMap());
    }
    return b.buildMap();
  }

  static listFrom(map: JsonMap | null, key: string): ModelView[] {
    const out: ModelView[] = [];
    if (map === null) {
      return out;
    }
    const arr: Object[] = JsonAccess.arr(map, key);
    for (const item of arr) {
      const m: JsonMap | null = JsonAccess.asMap(item);
      if (m !== null) {
        out.push(ModelView.fromJson(m));
      }
    }
    return out;
  }
}

export class ModelProviderGroup {
  id: string = '';
  name: string = '';
  models: ModelView[] = [];

  static fromJson(j: JsonMap | null): ModelProviderGroup {
    const g: ModelProviderGroup = new ModelProviderGroup();
    if (j === null) {
      return g;
    }
    g.id = JsonAccess.strOr(j, 'id', '');
    g.name = JsonAccess.strOr(j, 'name', g.id);
    g.models = ModelView.listFrom(j, 'models');
    return g;
  }

  static listFrom(map: JsonMap | null, key: string): ModelProviderGroup[] {
    const out: ModelProviderGroup[] = [];
    if (map === null) {
      return out;
    }
    const arr: Object[] = JsonAccess.arr(map, key);
    for (const item of arr) {
      const m: JsonMap | null = JsonAccess.asMap(item);
      if (m !== null) {
        out.push(ModelProviderGroup.fromJson(m));
      }
    }
    return out;
  }
}

export class ModelFailure {
  provider: string = '';
  message: string = '';

  static fromJson(j: JsonMap | null): ModelFailure {
    const f: ModelFailure = new ModelFailure();
    if (j === null) {
      return f;
    }
    f.provider = JsonAccess.strOr(j, 'provider', '');
    f.message = JsonAccess.strOr(j, 'message', '');
    return f;
  }

  static listFrom(map: JsonMap | null, key: string): ModelFailure[] {
    const out: ModelFailure[] = [];
    if (map === null) {
      return out;
    }
    const arr: Object[] = JsonAccess.arr(map, key);
    for (const item of arr) {
      const m: JsonMap | null = JsonAccess.asMap(item);
      if (m !== null) {
        out.push(ModelFailure.fromJson(m));
      }
    }
    return out;
  }
}

/** 当前选中模型三元组（也用于 select-model 应答的 data.selected）。 */
export class ModelSelection {
  provider: string = '';
  model: string = '';
  reasoningEffort: string | null = null;

  static fromJson(j: JsonMap | null): ModelSelection {
    const s: ModelSelection = new ModelSelection();
    if (j === null) {
      return s;
    }
    s.provider = JsonAccess.strOr(j, 'provider', '');
    s.model = JsonAccess.strOr(j, 'model', '');
    s.reasoningEffort = JsonAccess.str(j, 'reasoningEffort');
    return s;
  }

  toMap(): JsonMap {
    const b: WireBuilder = new WireBuilder();
    b.put('provider', this.provider);
    b.put('model', this.model);
    b.putIf(this.reasoningEffort !== null, 'reasoningEffort',
      this.reasoningEffort as Object | null);
    return b.buildMap();
  }
}

/** models 应答整体。 */
export class SessionModels {
  current: ModelSelection = new ModelSelection();
  routable: boolean = false;
  groups: ModelProviderGroup[] = [];
  failures: ModelFailure[] = [];

  static fromJson(j: JsonMap | null): SessionModels {
    const s: SessionModels = new SessionModels();
    if (j === null) {
      return s;
    }
    s.current = ModelSelection.fromJson(JsonAccess.obj(j, 'current'));
    s.routable = JsonAccess.boolOr(j, 'routable', false);
    s.groups = ModelProviderGroup.listFrom(j, 'groups');
    s.failures = ModelFailure.listFrom(j, 'failures');
    return s;
  }

  /** 从 gateway.sessionModels() 的原始 data 收敛。 */
  static parse(data: JsonMap | null): SessionModels {
    return SessionModels.fromJson(data);
  }
}

/**
 * 从 select-model 应答（kind=sent）提取 selected 三元组；
 * data.type != 'select-model' 或缺 selected 时返回 null（协议错误，
 * companion WsDomainPorts.kt:216-221 抛 WS_BAD_FRAME，这里交给 UI 提示）。
 */
export function parseSelectModelReply(data: JsonMap | null): ModelSelection | null {
  if (data === null) {
    return null;
  }
  const type: string = JsonAccess.strOr(data, 'type', '');
  if (type !== 'select-model') {
    return null;
  }
  const selected: JsonMap | null = JsonAccess.obj(data, 'selected');
  if (selected === null) {
    return null;
  }
  return ModelSelection.fromJson(selected);
}

/** reasoningEffort 的本地中文标签（off/low/high/max；未知回退原值）。 */
export function reasoningEffortLabel(id: string): string {
  if (id === 'off') {
    return '关闭';
  }
  if (id === 'low') {
    return '低';
  }
  if (id === 'high') {
    return '高';
  }
  if (id === 'max') {
    return '最高';
  }
  return id;
}
