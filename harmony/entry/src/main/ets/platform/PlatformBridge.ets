/**
 * 平台桥 —— core/Transport.ts TimerBridge 与存储/时区的平台实现。
 * - TimerBridge：ArkTS 全局 setTimeout/clearTimeout（返回 number）。
 * - timeZoneId：IANA 时区名，取不到回 'UTC'（与安卓 device.dart 同口径）。
 * - PrefsStore：@ohos.data.preferences 封装，供 Credentials/Hosts 持久化。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { bundleManager } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import type { TimerBridge } from '../core/Transport';
import { Dlog } from './Dlog';

export class ArkTimers implements TimerBridge {
  schedule(delayMs: number, action: () => void): number {
    return setTimeout(action, delayMs) as number;
  }

  cancel(handle: number): void {
    clearTimeout(handle);
  }
}

/**
 * 时区名（IANA）。真机实测 `new Intl.DateTimeFormat().resolvedOptions().timeZone`
 * 在本机 ArkTS 运行时返回 'America/Chicago'（错误值）——不能作首选。改走
 * @ohos.i18n 的 `getTimeZone().getID()`（系统时区库直出 IANA 名），失败才降级
 * Intl，再失败回 'UTC'（安卓 bridge/platform.dart 同样回退 'UTC'）。
 */
export function timeZoneId(): string {
  try {
    const zone: string = i18n.getTimeZone().getID();
    if (zone !== undefined && zone !== null && zone !== '') {
      return zone;
    }
  } catch (e) {
    // 继续走降级链。
  }
  try {
    const fmt = new Intl.DateTimeFormat();
    const zone: string | undefined = fmt.resolvedOptions().timeZone;
    if (zone !== undefined && zone !== '') {
      return zone;
    }
  } catch (e) {
    // 继续走回退。
  }
  return 'UTC';
}

/// 设备标识（安装期生成一次并持久化；安卓口径 dsh-chat-<ms36>）。
export class DeviceIdentity {
  static deviceId(): string {
    const now = Date.now();
    return 'dsh-chat-' + now.toString(36);
  }
}

/// 应用版本（bundleManager 读 versionName+versionCode；失败降级 '…'）。
/// 安卓 DshPlatform.appVersion() 同口径；设置页关于区展示。
export async function appVersion(): Promise<string> {
  try {
    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const name: string = info.versionName;
    const code: number = info.versionCode;
    return name + '+' + code.toString();
  } catch (err) {
    const e = err as BusinessError;
    Dlog.warn('[ver] failed code=' + e.code.toString() + ' msg=' + e.message);
    return '…';
  }
}

/**
 * Preferences 存取封装（应用级单例，EntryAbility 启动时 init）。
 * 键空间：dsh.credentials / dsh.hosts（core/Credentials.ts、core/Hosts.ts 的
 * STORAGE_KEY 常量）。
 */
export class PrefsStore {
  private static store: preferences.Preferences | null = null;

  static init(context: common.UIAbilityContext): void {
    if (PrefsStore.store === null) {
      const options: preferences.Options = { name: 'dsh' };
      preferences.getPreferences(context, options).then((pref: preferences.Preferences): void => {
        PrefsStore.store = pref;
      }).catch((e: BusinessError | Error): void => {
        // 初始化失败保持 null，读写侧降级为空数据。
      });
    }
  }

  static async getString(key: string): Promise<string | null> {
    const pref = PrefsStore.store;
    if (pref === null) {
      return null;
    }
    const value: preferences.ValueType = await pref.get(key, '');
    if (typeof value !== 'string' || value === '') {
      return null;
    }
    return value;
  }

  static async putString(key: string, value: string): Promise<void> {
    const pref = PrefsStore.store;
    if (pref === null) {
      return;
    }
    await pref.put(key, value);
    await pref.flush();
  }

  static async removeKey(key: string): Promise<void> {
    const pref = PrefsStore.store;
    if (pref === null) {
      return;
    }
    await pref.delete(key);
    await pref.flush();
  }
}
