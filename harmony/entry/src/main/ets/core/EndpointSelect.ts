/**
 * 候选地址探活择优（IKX5KQ）——移植 app/lib/bridge/endpoint_select.dart 的纯逻辑部分。
 *
 * 桥把 DSH1 里的 endpoints 从一条改成**有序候选列表**（隧道在前，其后是局域网/
 * 虚拟网地址）。客户端要「在家走 LAN、在外走隧道」，就必须保留全部候选，连接时
 * 探活择优、失败换下一条。本文件只做分类/排序/诊断文案，真探活留给平台层
 * （core 禁 import @kit，见 PORT-MAP §分层铁律）。
 */

export enum EndpointKind {
  LAN = 0,
  TUNNEL = 1,
  OTHER = 2,
}

/** 单条探活结果（平台层填，纯逻辑层只读）。 */
export class EndpointProbe {
  baseUrl: string = '';
  ok: boolean = false;
  /** 毫秒；不可达时为 -1。 */
  latencyMs: number = -1;
  error: string = '';

  constructor(baseUrl: string, ok: boolean, latencyMs: number, error: string) {
    this.baseUrl = baseUrl;
    this.ok = ok;
    this.latencyMs = latencyMs;
    this.error = error;
  }

  kind(): EndpointKind {
    return classifyEndpoint(this.baseUrl);
  }

  /** 诊断短句：「192.168.1.5:3090 42ms」/「…trycloudflare.com 探活超时」。 */
  label(): string {
    const shown: string = this.baseUrl.replace(/^https?:\/\//, '');
    if (this.ok) {
      return shown + ' ' + String(this.latencyMs) + 'ms';
    }
    return shown + ' ' + (this.error.length > 0 ? this.error : '不可达');
  }
}

/** 从 URL 取 host（core 不依赖 URL 类：手工剥协议、路径与端口）。 */
export function hostOf(baseUrl: string): string {
  let s: string = baseUrl.trim();
  s = s.replace(/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//, '');
  const slash: number = s.indexOf('/');
  if (slash >= 0) {
    s = s.substring(0, slash);
  }
  const at: number = s.lastIndexOf('@');
  if (at >= 0) {
    s = s.substring(at + 1);
  }
  if (s.startsWith('[')) {
    const close: number = s.indexOf(']');
    return close > 0 ? s.substring(0, close + 1).toLowerCase() : s.toLowerCase();
  }
  const colon: number = s.indexOf(':');
  if (colon >= 0) {
    s = s.substring(0, colon);
  }
  return s.toLowerCase();
}

/** 私有/虚拟网地址：10/8、172.16/12、192.168/16、100.64/10（CGNAT）、回环、.local、IPv6 ULA。 */
export function isPrivateHost(host: string): boolean {
  if (host.length === 0) {
    return false;
  }
  const h: string = host.toLowerCase();
  if (h === 'localhost' || h.endsWith('.local')) {
    return true;
  }
  const m: RegExpMatchArray | null = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m !== null) {
    const a: number = parseInt(m[1], 10);
    const b: number = parseInt(m[2], 10);
    if (a === 127 || a === 10) {
      return true;
    }
    if (a === 192 && b === 168) {
      return true;
    }
    if (a === 172 && b >= 16 && b <= 31) {
      return true;
    }
    if (a === 100 && b >= 64 && b <= 127) {
      return true;
    }
    return false;
  }
  if (h.startsWith('[')) {
    const v6: string = h.substring(1, h.length - 1);
    return v6 === '::1' || v6.startsWith('fc') || v6.startsWith('fd') || v6.startsWith('fe80');
  }
  return false;
}

export function classifyEndpoint(baseUrl: string): EndpointKind {
  const host: string = hostOf(baseUrl);
  if (host.indexOf('trycloudflare.com') >= 0 || host.indexOf('ngrok') >= 0
    || host.indexOf('tunnel') >= 0) {
    return EndpointKind.TUNNEL;
  }
  if (isPrivateHost(host)) {
    return EndpointKind.LAN;
  }
  return EndpointKind.OTHER;
}

/** 去重保序、去首尾空白与尾斜杠。 */
export function normalizeEndpoints(raw: string[]): string[] {
  const out: string[] = [];
  for (const e of raw) {
    const v: string = e.trim().replace(/\/+$/, '');
    if (v.length === 0 || out.indexOf(v) >= 0) {
      continue;
    }
    out.push(v);
  }
  return out;
}

/**
 * 择优：可达里 LAN（延迟 ≤ 最快×1.5）优先，其次按延迟，并列看上次成功地址。
 * 全不可达返回 null（companion EndpointSelection.rank 口径）。
 */
export function pickEndpoint(probes: EndpointProbe[], preferred: string | null): string | null {
  const ok: EndpointProbe[] = [];
  for (const p of probes) {
    if (p.ok) {
      ok.push(p);
    }
  }
  if (ok.length === 0) {
    return null;
  }
  let fastest: number = Number.MAX_SAFE_INTEGER;
  for (const p of ok) {
    const ms: number = p.latencyMs < 0 ? Number.MAX_SAFE_INTEGER : p.latencyMs;
    if (ms < fastest) {
      fastest = ms;
    }
  }
  const cutoff: number = Math.round(fastest * 1.5);
  ok.sort((a: EndpointProbe, b: EndpointProbe): number => {
    const ra: number = rankOf(a, cutoff);
    const rb: number = rankOf(b, cutoff);
    if (ra !== rb) {
      return ra - rb;
    }
    const la: number = a.latencyMs < 0 ? Number.MAX_SAFE_INTEGER : a.latencyMs;
    const lb: number = b.latencyMs < 0 ? Number.MAX_SAFE_INTEGER : b.latencyMs;
    if (la !== lb) {
      return la - lb;
    }
    if (preferred !== null) {
      if (a.baseUrl === preferred) {
        return -1;
      }
      if (b.baseUrl === preferred) {
        return 1;
      }
    }
    return 0;
  });
  return ok[0].baseUrl;
}

function rankOf(p: EndpointProbe, cutoff: number): number {
  const ms: number = p.latencyMs < 0 ? Number.MAX_SAFE_INTEGER : p.latencyMs;
  return p.kind() === EndpointKind.LAN && ms <= cutoff ? 0 : 1;
}

/** 一句诊断：「试了 2 条：LAN 42ms、隧道 380ms → 选 LAN（局域网优先）」。 */
export function selectionNote(probes: EndpointProbe[], chosen: string | null): string {
  if (probes.length === 0) {
    return '';
  }
  const tried: string[] = [];
  for (const p of probes) {
    tried.push(p.label());
  }
  const joined: string = tried.join('、');
  if (chosen === null) {
    return '试了 ' + String(probes.length) + ' 条都不通：' + joined;
  }
  let why: string = '按延迟择优';
  for (const p of probes) {
    if (p.baseUrl === chosen && p.kind() === EndpointKind.LAN) {
      why = '局域网优先';
    }
  }
  const shown: string = chosen.replace(/^https?:\/\//, '');
  return '试了 ' + String(probes.length) + ' 条：' + joined + ' → 选 ' + shown + '（' + why + '）';
}
