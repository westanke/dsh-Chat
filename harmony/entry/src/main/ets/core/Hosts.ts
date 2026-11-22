/**
 * 桥配置导入与主机记录 —— 移植 app/lib/bridge/hosts.dart。
 *
 * 线格式对齐 dsh-companion 的 ConnectionShare（DSH1）：
 * `DSH1:` + URL-safe 无填充 Base64(JSON{displayName, endpoints, token?, ...})。
 * 解码宽容（companion ConnectionShare.kt:62-308 口径）：剔空白/零宽字符、
 * 前缀大小写不敏感且可在全文任意位置、双 Base64 字母表、自动补 `=`、
 * 失败一律返回 null 不抛异常。
 *
 * 存储取明文 JSON 数组（与安卓 shared_preferences 同口径）；持久化留 entry 层，
 * 本文件只放纯数据与纯函数（node 直测）。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { normalizeEndpoints } from './EndpointSelect';
import { WireBuilder } from './Wire';

/** 一条主机记录（导入/配对成功后落库；点击即可直连）。 */
export class DshHost {
  id: string = '';
  displayName: string = '';

  /** 最近一次连通/导入时的首个地址（老单地址码就是它本身）。 */
  baseUrl: string = '';
  token: string | null = null;
  lastUsedAt: number = 0;

  /** DSH1 endpoints 的全部候选（隧道在前，其后 LAN/虚拟网）；老记录为空。 */
  endpoints: string[] = [];

  /** 上次连接成功的地址（下次先试它，失败立刻换）。 */
  preferredEndpoint: string | null = null;

  static fromJson(j: JsonMap | null): DshHost {
    const h: DshHost = new DshHost();
    if (j === null) {
      return h;
    }
    h.id = JsonAccess.strOr(j, 'id', '');
    h.displayName = JsonAccess.strOr(j, 'displayName', '');
    h.baseUrl = JsonAccess.strOr(j, 'baseUrl', '');
    const token: string | null = JsonAccess.str(j, 'token');
    h.token = token === null || token.length === 0 ? null : token;
    h.lastUsedAt = JsonAccess.numOr(j, 'lastUsedAt', 0);
    const eps: Object[] = JsonAccess.arr(j, 'endpoints');
    for (const e of eps) {
      if (typeof e === 'string') {
        h.endpoints.push(e as string);
      }
    }
    const pref: string | null = JsonAccess.str(j, 'preferredEndpoint');
    h.preferredEndpoint = pref === null || pref.length === 0 ? null : pref;
    return h;
  }

  toMap(): JsonMap {
    const b: WireBuilder = new WireBuilder();
    b.put('id', this.id);
    b.put('displayName', this.displayName);
    b.put('baseUrl', this.baseUrl);
    b.putIf(this.token !== null, 'token', this.token as Object | null);
    b.put('lastUsedAt', this.lastUsedAt);
    b.put('endpoints', this.endpoints);
    b.putIf(this.preferredEndpoint !== null, 'preferredEndpoint',
      this.preferredEndpoint as Object | null);
    return b.buildMap();
  }
}

/** 连接时应试的地址表：baseUrl + endpoints 去重保序（老记录只有 baseUrl）。 */
export function candidatesOf(host: DshHost): string[] {
  const raw: string[] = [host.baseUrl];
  for (const e of host.endpoints) {
    raw.push(e);
  }
  return normalizeEndpoints(raw);
}

/**
 * FNV-1a 64 位摘要，hex 16 字符。幂等键只要求「同输入同输出」，FNV 足够——
 * 注意不能用 base64 前缀截断：相似 URL 的 base64 前 16 位完全相同
 * （真机测试踩过：192.168.1.10 与 .11 的 base64 前 16 位一致）。
 * JS 位运算只有 32 位，用 BigInt 实现 64 位乘法；输入先手写 UTF-8 编码
 * （core 不 import @kit，零平台依赖）。
 */
export function stableId(baseUrl: string): string {
  let hash: bigint = BigInt('0xcbf29ce484222325');
  const bytes: number[] = utf8Bytes(baseUrl);
  for (const unit of bytes) {
    hash = hash ^ BigInt(unit);
    hash = (hash * BigInt('0x100000001b3')) & BigInt('0xFFFFFFFFFFFFFFFF');
  }
  let hex: string = hash.toString(16);
  while (hex.length < 16) {
    hex = '0' + hex;
  }
  return hex;
}

/** 手写 UTF-8 编码（ASCII 快路径 + 多字节逐字节展开），与 TextEncoder 等价。 */
function utf8Bytes(input: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < input.length; i++) {
    const code: number = input.charCodeAt(i);
    if (code < 0x80) {
      out.push(code);
    } else if (code < 0x800) {
      out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < input.length) {
      const lo: number = input.charCodeAt(i + 1);
      if (lo >= 0xdc00 && lo <= 0xdfff) {
        const cp: number = 0x10000 + ((code - 0xd800) << 10) + (lo - 0xdc00);
        out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f),
          0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
        i++;
      } else {
        out.push(0xef, 0xbf, 0xbd); // 孤立代理对 → U+FFFD
      }
    } else {
      out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }
  return out;
}

/** 标准 Base64 解码（容错版：容忍空白已剔除后的输入），失败回 null。 */
function base64Decode(input: string): number[] | null {
  const alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const table: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < alphabet.length; i++) {
    table.set(alphabet.charAt(i), i);
  }
  const clean: string = input.replace(/=/g, '');
  let bits: number = 0;
  let acc: number = 0;
  const out: number[] = [];
  for (let i = 0; i < clean.length; i++) {
    const v: number | undefined = table.get(clean.charAt(i));
    if (v === undefined) {
      return null;
    }
    acc = (acc << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >> bits) & 0xff);
    }
  }
  return out;
}

/** UTF-8 字节数组 → 字符串（手写解码，容忍非法序列替换 U+FFFD）。 */
function utf8FromBytes(bytes: number[]): string {
  let out: string = '';
  for (let i = 0; i < bytes.length;) {
    const b0: number = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i += 1;
    } else if ((b0 & 0xe0) === 0xc0 && i + 1 < bytes.length
      && (bytes[i + 1] & 0xc0) === 0x80) {
      out += String.fromCharCode(((b0 & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
      i += 2;
    } else if ((b0 & 0xf0) === 0xe0 && i + 2 < bytes.length
      && (bytes[i + 1] & 0xc0) === 0x80 && (bytes[i + 2] & 0xc0) === 0x80) {
      out += String.fromCharCode(((b0 & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6)
        | (bytes[i + 2] & 0x3f));
      i += 3;
    } else if ((b0 & 0xf8) === 0xf0 && i + 3 < bytes.length
      && (bytes[i + 1] & 0xc0) === 0x80 && (bytes[i + 2] & 0xc0) === 0x80
      && (bytes[i + 3] & 0xc0) === 0x80) {
      const cp: number = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12)
        | ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f);
      const hi: number = 0xd800 + ((cp - 0x10000) >> 10);
      const lo: number = 0xdc00 + ((cp - 0x10000) & 0x3ff);
      out += String.fromCharCode(hi, lo);
      i += 4;
    } else {
      out += String.fromCharCode(0xfffd);
      i += 1;
    }
  }
  return out;
}

/**
 * DSH1 配置文本解码（宽容版，companion ConnectionShare.decode 口径）。
 * 失败返回 null（绝不抛异常）。nowMs 由调用方传入（可测性）。
 */
export function decodeDsh1(text: string, nowMs: number): DshHost | null {
  try {
    // 1) 定位前缀（大小写不敏感，可在全文任意位置）；无前缀则整段当 base64 试。
    const noSpace: string = text.replace(/\s+/g, '').replace(/[\u200b-\u200f\u2060\ufeff]/g, '');
    const lower: string = noSpace.toLowerCase();
    const idx: number = lower.indexOf('dsh1:');
    let payload: string = idx >= 0 ? noSpace.substring(idx + 5) : noSpace;
    if (payload.length === 0) {
      return null;
    }
    // 2) 剔除 Base64 字母表外字符（结尾粘上的标点/引号）。
    payload = payload.replace(/[^A-Za-z0-9_\-=]/g, '');
    if (payload.length === 0) {
      return null;
    }
    // 3) URL-safe → 标准 + 补 `=`。
    let std: string = payload.replace(/_/g, '/').replace(/-/g, '+');
    const mod: number = std.length % 4;
    if (mod === 1) {
      return null;
    }
    if (mod !== 0) {
      std += '='.repeat(4 - mod);
    }
    const bytes: number[] | null = base64Decode(std);
    if (bytes === null) {
      return null;
    }
    const json: string = utf8FromBytes(bytes);
    // 4) 整段解析；失败截最外层 `{...}` 再试。
    let parsed: Object | null = JsonAccess.parse(json);
    if (parsed === null) {
      const start: number = json.indexOf('{');
      const end: number = json.lastIndexOf('}');
      if (start < 0 || end <= start) {
        return null;
      }
      parsed = JsonAccess.parse(json.substring(start, end + 1));
    }
    const map: JsonMap | null = JsonAccess.asMap(parsed);
    if (map === null) {
      return null;
    }
    // 5) 提字段：endpoints 全留（IKX5KQ——隧道在首个，其后 LAN/虚拟网；
    // 只取首个会让「在家生成的码出门连不上」/「出门的码回家绕远」）。
    const rawEndpoints: Object[] = JsonAccess.arr(map, 'endpoints');
    const urls: string[] = [];
    for (const e of rawEndpoints) {
      const item: JsonMap | null = JsonAccess.asMap(e);
      if (item === null) {
        continue;
      }
      const u: string = JsonAccess.strOr(item, 'baseUrl', '').trim();
      if (u.length === 0) {
        continue;
      }
      urls.push(u.replace(/\/api\/v1\/?$/, ''));
    }
    // 兼容极老的码：顶层 baseUrl。
    const topLevel: string = JsonAccess.strOr(map, 'baseUrl', '').trim();
    if (topLevel.length > 0) {
      urls.push(topLevel.replace(/\/api\/v1\/?$/, ''));
    }
    const candidates: string[] = normalizeEndpoints(urls);
    if (candidates.length === 0) {
      return null;
    }
    const baseUrl: string = candidates[0];
    let displayName: string = JsonAccess.strOr(map, 'displayName', '').trim();
    if (displayName.length === 0) {
      displayName = '导入的主机';
    }
    const token: string | null = JsonAccess.str(map, 'token');
    const host: DshHost = new DshHost();
    host.id = stableId(baseUrl);
    host.displayName = displayName;
    host.baseUrl = baseUrl;
    host.token = token === null || token.length === 0 ? null : token;
    host.lastUsedAt = nowMs;
    host.endpoints = candidates;
    host.preferredEndpoint = baseUrl;
    return host;
  } catch (e) {
    return null;
  }
}

/** 主机列表纯操作：按 baseUrl 幂等 upsert，lastUsedAt 降序（安卓 DshHosts.upsert）。 */
export function upsertHost(hosts: DshHost[], host: DshHost): DshHost[] {
  const out: DshHost[] = hosts.slice();
  let idx: number = -1;
  for (let i = 0; i < out.length; i++) {
    // 同一主机可能经不同地址连过（LAN/隧道）：id 相同也算同一条，
    // 否则换个地址连一次就多出一行历史主机（IKX5KQ）。
    if ((host.id.length > 0 && out[i].id === host.id) || out[i].baseUrl === host.baseUrl) {
      idx = i;
      break;
    }
  }
  if (idx >= 0) {
    out[idx] = host;
  } else {
    out.push(host);
  }
  out.sort((a: DshHost, b: DshHost): number => b.lastUsedAt - a.lastUsedAt);
  return out;
}

/**
 * 删除单条主机记录：按 baseUrl 优先、id 兜底匹配（兼容早期 id 缺失的历史数据）。
 * 返回删后的列表与是否命中。
 */
export function removeHost(hosts: DshHost[], host: DshHost): DshHost[] {
  const out: DshHost[] = [];
  for (const h of hosts) {
    const hit: boolean = h.baseUrl === host.baseUrl
      || (host.id.length > 0 && h.id === host.id);
    if (!hit) {
      out.push(h);
    }
  }
  return out;
}

/** 存储键（entry 层 preferences 用，与安卓 shared_preferences 同名）。 */
export const HOSTS_STORAGE_KEY: string = 'dsh.hosts';

/** 从存储原始 JSON 解析列表（坏形状逐条过滤，绝不抛）。 */
export function parseHosts(raw: string): DshHost[] {
  if (raw.length === 0) {
    return [];
  }
  const parsed: Object | null = JsonAccess.parse(raw);
  const arr: Object[] = JsonAccess.asMap(parsed) === null && Array.isArray(parsed)
    ? parsed as Object[]
    : [];
  const out: DshHost[] = [];
  for (const item of arr) {
    const map: JsonMap | null = JsonAccess.asMap(item);
    if (map !== null) {
      out.push(DshHost.fromJson(map));
    }
  }
  return out;
}

/** 列表序列化为存储 JSON。 */
export function encodeHosts(hosts: DshHost[]): string {
  const arr: Object[] = [];
  for (const h of hosts) {
    arr.push(h.toMap());
  }
  return JSON.stringify(arr);
}
