/**
 * 权限档位目录与本地化标签 —— 移植 app/lib/bridge/permissions.dart。
 *
 * 权威清单来自服务端 `permission-options` 应答（内核 permissionPresets.catalog()
 * 的透传），**不硬编码四档**：默认部署只有 workspace-write / danger-full-access
 * 两个 preset（read-only 是合法 sandbox 模式但没有默认 preset，切换会失败；
 * auto 只在 live Auto 集成注册时出现；custom 是派生态、永不可切）。
 * UI 上 options 里没有的档位一律不显示。
 */

import { JsonAccess, JsonMap } from './JsonAccess';

export class PermissionOption {
  value: string = '';
  name: string = '';
  description: string | null = null;

  static fromJson(j: JsonMap | null): PermissionOption {
    const o: PermissionOption = new PermissionOption();
    if (j === null) {
      return o;
    }
    o.value = JsonAccess.strOr(j, 'value', '');
    o.name = JsonAccess.strOr(j, 'name', o.value);
    o.description = JsonAccess.str(j, 'description');
    return o;
  }

  static listFrom(map: JsonMap | null, key: string): PermissionOption[] {
    const out: PermissionOption[] = [];
    if (map === null) {
      return out;
    }
    const arr: Object[] = JsonAccess.arr(map, key);
    for (const item of arr) {
      const m: JsonMap | null = JsonAccess.asMap(item);
      if (m !== null) {
        out.push(PermissionOption.fromJson(m));
      }
    }
    return out;
  }

  toMap(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['value'] = this.value;
    out['name'] = this.name;
    if (this.description !== null) {
      out['description'] = this.description;
    }
    return out;
  }

  /**
   * 本地中文标签（对照 companion ChatPermissionMenu.permissionLabel；
   * 用户口径：仅可查看/工作区读写/完全权限/自动审查）。未识别回退服务端 name。
   */
  get label(): string {
    if (this.value === 'read-only') {
      return '仅可查看';
    }
    if (this.value === 'workspace-write') {
      return '工作区读写';
    }
    if (this.value === 'danger-full-access') {
      return '完全权限';
    }
    if (this.value === 'auto') {
      return '自动审查';
    }
    if (this.value === 'custom') {
      return '自定义';
    }
    return this.name;
  }

  /** 本地中文说明；未识别回退服务端 description。 */
  get descriptionLabel(): string | null {
    if (this.value === 'read-only') {
      return '只能查看会话内容，不能写入';
    }
    if (this.value === 'workspace-write') {
      return '可以在工作区内读写文件';
    }
    if (this.value === 'danger-full-access') {
      return '不受沙箱限制，操作前请确认';
    }
    if (this.value === 'auto') {
      return '按风险自动决定是否需要确认';
    }
    if (this.description !== null && this.description.length > 0) {
      return this.description;
    }
    return null;
  }

  /** 是否需要二次确认（对照 companion：danger-full-access 必须确认）。 */
  get needsConfirm(): boolean {
    return this.value === 'danger-full-access';
  }

  /** 派生态，不能作为切换目标（内核保留值）。 */
  get isDerived(): boolean {
    return this.value === 'custom';
  }
}

/** permission-options 应答整体（{options, defaultPreset}）。 */
export class PermissionCatalog {
  options: PermissionOption[] = [];
  defaultPreset: string | null = null;

  static fromJson(j: JsonMap | null): PermissionCatalog {
    const c: PermissionCatalog = new PermissionCatalog();
    if (j === null) {
      return c;
    }
    c.options = PermissionOption.listFrom(j, 'options');
    c.defaultPreset = JsonAccess.str(j, 'defaultPreset');
    return c;
  }

  /**
   * 服务端默认档位（只用于「未设置过」时的初始显示，**不当当前值**——
   * companion Models.kt:230-236 的刻意取舍）。
   */

  /** 可切换的档位（过滤 custom）。 */
  get switchable(): PermissionOption[] {
    const out: PermissionOption[] = [];
    for (const o of this.options) {
      if (!o.isDerived) {
        out.push(o);
      }
    }
    return out;
  }
}

/**
 * 当前会话权限档位的本地中文标签（投影 values.permissions 的 currentValue）。
 * 未知值原样返回，绝不绝不杜撰档位。
 */
export function permissionLabelOf(value: string | null): string {
  if (value === null || value.length === 0) {
    return '权限未设置';
  }
  // 复用 PermissionOption 的映射表（构造一个轻量对象查询，安卓同款）。
  const probe: PermissionOption = new PermissionOption();
  probe.value = value;
  probe.name = value;
  return probe.label;
}
