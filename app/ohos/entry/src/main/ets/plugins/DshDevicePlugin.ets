/**
 * 设备信息插件 —— Flutter MethodChannel `dsh/device`。
 *
 * 对齐安卓 MainActivity.kt 的 dsh/device 通道（:35）：
 * - `ianaZone`  → 时区 IANA 名（安卓回 TimeZone.getDefault().id）
 * - `deviceName` → 当前设备展示名（市场名/型号）
 * - `filesDir`  → 应用沙盒 files 目录绝对路径（安卓无此方法，鸿蒙新增；
 *                 Dart 侧 bridge/dlog.dart 用它写日志文件——Dart 拿不到
 *                 context.filesDir，只能由原生回传）
 *
 * 鸿蒙侧时区口径与安卓对齐成 IANA 名：优先 @ohos.i18n 的 getTimeZone().getID()
 * （系统时区库直出 IANA 名），失败才降级 Intl，再失败回 'UTC'。
 * 真机实测 Intl 在部分鸿蒙设备上返回错误值（'America/Chicago'），不能作首选。
 */

import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';

/**
 * 取 IANA 时区名；取不到回 'UTC'（与安卓 bridge/device.dart 同口径）。
 */
export function deviceTimeZoneId(): string {
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

export default class DshDevicePlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;

  getUniqueClassName(): string {
    return 'DshDevicePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'dsh/device');
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        switch (call.method) {
          case 'ianaZone':
            result.success(deviceTimeZoneId());
            break
          case 'deviceName':
            result.success(this.deviceDisplayName());
            break;
          case 'filesDir':
            result.success(this.filesDir());
            break;
          default:
            result.notImplemented();
            break;
        }
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.context = null;
  }


  /** 当前设备展示名：优先市场名，回退产品型号，再回退 HarmonyOS。 */
  private deviceDisplayName(): string {
    try {
      const market: string = deviceInfo.marketName;
      if (market !== undefined && market !== null && market.trim() !== '') {
        return market.trim();
      }
      const model: string = deviceInfo.productModel;
      if (model !== undefined && model !== null && model.trim() !== '') {
        return model.trim();
      }
    } catch (e) {
      // 继续回退。
    }
    return 'HarmonyOS';
  }

  /** 应用沙盒 files 目录；拿不到 context 时回空串（Dart 侧会回退到相对路径）。 */
  private filesDir(): string {
    const ctx = this.context;
    if (ctx === null) {
      return '';
    }
    try {
      return ctx.filesDir;
    } catch (e) {
      return '';
    }
  }
}
