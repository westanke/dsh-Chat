/// REST 文件模型 —— 对齐安卓 gateway_rest.dart 的 GatewayRoot/GatewayEntry
/// 与 gateway_api.dart 的 ResolvedFile（roots/entries REST 端点）。
/// @ 文件引用面板与 .md 全屏查看用。字段一律默认值（宽容解析口径）。
import { JsonAccess, JsonMap } from './JsonAccess';
import { WireBuilder } from './Wire';

/** 授权根（GET /api/v1/roots 的 items[] 项）。 */
export class GatewayRoot {
  id: string = '';
  label: string = '';

  static fromJson(j: JsonMap | null): GatewayRoot {
    const r: GatewayRoot = new GatewayRoot();
    r.id = JsonAccess.strOr(j, 'id', '');
    r.label = JsonAccess.strOr(j, 'label', '');
    return r;
  }

  static listFrom(map: JsonMap | null, key: string): GatewayRoot[] {
    const out: GatewayRoot[] = [];
    const arr: Object[] = JsonAccess.arr(map, key);
    for (const raw of arr) {
      out.push(GatewayRoot.fromJson(JsonAccess.asMap(raw)));
    }
    return out;
  }
}

/** 根下条目（GET /api/v1/roots/{id}/entries 的 entries[] 项；只留 file/directory）。 */
export class GatewayEntry {
  name: string = '';
  path: string = '';
  kind: string = '';
  isDirectory: boolean = false;

  static fromJson(j: JsonMap | null): GatewayEntry | null {
    const kind: string = JsonAccess.strOr(j, 'kind', '');
    // 只留 file/directory（其余 kind 不进面板）。
    if (kind !== 'file' && kind !== 'directory') {
      return null;
    }
    const e: GatewayEntry = new GatewayEntry();
    e.name = JsonAccess.strOr(j, 'name', '');
    e.path = JsonAccess.strOr(j, 'path', '');
    e.kind = kind;
    e.isDirectory = kind === 'directory';
    return e;
  }

  /** 目录优先 + name 小写比较（安卓 listEntries 的排序口径）。 */
  static sortList(list: GatewayEntry[]): void {
    list.sort((a: GatewayEntry, b: GatewayEntry): number => {
      if (a.isDirectory !== b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1;
    });
  }
}

/** 路径解析结果（GET /api/v1/roots/resolve；md 全屏查看定位文件用）。 */
export class ResolvedFile {
  rootId: string = '';
  path: string = '';
  size: number = 0;
  contentType: string = '';

  static fromJson(j: JsonMap | null): ResolvedFile {
    const r: ResolvedFile = new ResolvedFile();
    r.rootId = JsonAccess.strOr(j, 'rootId', '');
    r.path = JsonAccess.strOr(j, 'path', '');
    r.size = JsonAccess.numOr(j, 'size', 0);
    r.contentType = JsonAccess.strOr(j, 'contentType', '');
    return r;
  }
}

/** 帮助：构造（预留，协议字段当前无上行）。 */
export function gatewayEntryToMap(e: GatewayEntry): JsonMap {
  const b: WireBuilder = new WireBuilder();
  b.put('name', e.name);
  b.put('path', e.path);
  b.put('kind', e.kind);
  return b.buildMap();
}
