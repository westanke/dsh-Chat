/**
 * 应用新版本检测（纯解析部分）—— 移植 app/lib/bridge/release_check.dart。
 *
 * 发布通道：release.sh 把 APK 同时发到 Gitee 与 GitHub Release。
 * 鸿蒙口径差异（PORT-MAP）：鸿蒙应用不能自安装 APK —— 鸿蒙版只做
 * 「查新版 + 引导去 Gitee/AGC」，不做原生下载/安装（platform.downloadApk
 * /installApk 无对应物）；HTTP 拉取留 entry 层（@ohos.net.http）。
 *
 * 对比口径：tag_name（`v1.0.0`）去掉 `v` 前缀后按语义化版本三段比较。
 */

import { JsonAccess, JsonMap } from './JsonAccess';

export const RELEASE_REPO: string = 'westanke/dsh-Chat';

/** 一条可下载的发布信息。 */
export class ReleaseInfo {
  tag: string = ''; // 如 v1.0.1
  apkUrl: string = '';
  apkName: string = '';
  size: number | null = null; // 字节；API 给了才有
  notes: string = ''; // 发布正文（Markdown 纯文本用）

  /** 语义化版本三段（tag 去 v 前缀；解析失败回 0.0.0）。 */
  get versionParts(): number[] {
    const t: string = this.tag.startsWith('v') ? this.tag.substring(1) : this.tag;
    const parts: string[] = t.split('.');
    const out: number[] = [];
    for (let i = 0; i < 3; i++) {
      if (i < parts.length) {
        const n: number = parseInt(parts[i], 10);
        out.push(isNaN(n) ? 0 : n);
      } else {
        out.push(0);
      }
    }
    return out;
  }
}

/**
 * 从 Gitee/GitHub 的 release JSON 里挑出 APK 资产。
 * 两站形状一致：tag_name / body / assets[]{name,browser_download_url,size}。
 * 历史命名两套都放行：release.sh 的 dsh-Chat-v*.apk 与
 * sync-gitee-release.sh 的 dshchat-*_N-android.apk（dsh-chat- 与
 * dshchat- 是两个不同前缀，都要显式匹配）。
 */
export function releaseFromJson(body: JsonMap | null): ReleaseInfo | null {
  if (body === null) {
    return null;
  }
  const tag: string = JsonAccess.strOr(body, 'tag_name', '');
  if (tag.length === 0) {
    return null;
  }
  const assets: Object[] = JsonAccess.arr(body, 'assets');
  for (const item of assets) {
    const a: JsonMap | null = JsonAccess.asMap(item);
    if (a === null) {
      continue;
    }
    const name: string = JsonAccess.strOr(a, 'name', '');
    if (!name.endsWith('.apk')) {
      continue;
    }
    const lower: string = name.toLowerCase();
    if (!lower.startsWith('dsh-chat-') && !lower.startsWith('dshchat-')) {
      continue;
    }
    const url: string = JsonAccess.strOr(a, 'browser_download_url', '');
    if (url.length === 0) {
      continue;
    }
    const info: ReleaseInfo = new ReleaseInfo();
    info.tag = tag;
    info.apkUrl = url;
    info.apkName = name;
    info.size = JsonAccess.num(a, 'size');
    info.notes = JsonAccess.strOr(body, 'body', '');
    return info;
  }
  return null;
}

/** a 是否比 b 新（语义化三段逐位比较）。 */
export function isNewerVersion(a: number[], b: number[]): boolean {
  for (let i = 0; i < 3; i++) {
    const ai: number = i < a.length ? a[i] : 0;
    const bi: number = i < b.length ? b[i] : 0;
    if (ai !== bi) {
      return ai > bi;
    }
  }
  return false;
}
