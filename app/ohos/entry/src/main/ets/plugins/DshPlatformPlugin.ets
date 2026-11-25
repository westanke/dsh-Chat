/**
 * 平台能力插件 —— Flutter MethodChannel `dsh/platform`。
 *
 * 对齐安卓 MainActivity.kt 的 dsh/platform（:116）：
 *   speak / stopSpeak / share / pickImage / appVersion /
 *   downloadApk / downloadStatus / installApk / openFile
 *
 * 鸿蒙口径：
 * - speak/stopSpeak → CoreSpeechKit（platform/Tts.ets）；
 * - share → ShareKit（platform/Share.ets）；
 * - pickImage → 系统相册 picker，读字节嗅探后复制进 cacheDir（platform/PhotoPick.ets）；
 * - appVersion → bundleManager 读 versionName/versionCode（由 Flutter 工具链从 pubspec 注入）；
 * - downloadApk/downloadStatus/installApk → 鸿蒙是应用市场分发制，不能自更新，
 *   返回失败占位（Dart 侧 supportsInAppUpdate=false 不会走到这里）；
 * - openFile → 字节写 cacheDir 后 startAbility(ohos.want.action.viewData)。
 *
 * UI 上下文来自 AbilityAware：configureFlutterEngine 阶段引擎已 attachToAbility，
 * add() 会立即回调 onAttachedToAbility。
 */

import { common, wantConstant, Want } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { pickImage, PickedPhoto } from '../platform/PhotoPick';
import { shareText } from '../platform/Share';
import { speak, stopSpeak } from '../platform/Tts';
import { Dlog } from '../platform/Dlog';

export default class DshPlatformPlugin implements FlutterPlugin, AbilityAware {
  private channel: MethodChannel | null = null;
  private uiContext: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return 'DshPlatformPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'dsh/platform');
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handle(call, result);
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.uiContext = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.uiContext = binding.getAbility().context as common.UIAbilityContext;
  }

  onDetachedFromAbility(): void {
    this.uiContext = null;
  }

  /** 通道方法分派（每个分支恰好回一次 result）。 */
  private handle(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'appVersion':
        this.reportAppVersion(result);
        break;
      case 'speak':
        speak(call.args as string)
          .then((ok: boolean) => {
            result.success(ok);
          })
          .catch((e: Object) => {
            Dlog.warn('speak failed: ' + JSON.stringify(e));
            result.success(false);
          });
        break;
      case 'stopSpeak':
        stopSpeak();
        result.success(null);
        break;
      case 'share':
        this.handleShare(call.args as string, result);
        break;
      case 'pickImage':
        this.handlePickImage(result);
        break;
      case 'downloadApk':
        // 鸿蒙不允许应用自更新（应用市场审核制）。
        result.success(-1);
        break;
      case 'downloadStatus':
        result.success(null);
        break;
      case 'installApk':
        result.success(false);
        break;
      case 'openFile':
        this.handleOpenFile(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  /** 本机安装版本 "versionName+versionCode" 的两个字段。 */
  private reportAppVersion(result: MethodResult): void {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const map: Map<string, Object> = new Map<string, Object>();
      map.set('version', info.versionName);
      map.set('code', info.versionCode);
      result.success(map);
    } catch (e) {
      Dlog.warn('appVersion failed: ' + JSON.stringify(e));
      result.success(null);
    }
  }

  private handleShare(text: string, result: MethodResult): void {
    const ctx: common.UIAbilityContext | null = this.uiContext;
    if (ctx === null) {
      result.success(false);
      return;
    }
    shareText(ctx, text)
      .then((ok: boolean) => {
        result.success(ok);
      })
      .catch((e: Object) => {
        Dlog.warn('share failed: ' + JSON.stringify(e));
        result.success(false);
      });
  }

  private handlePickImage(result: MethodResult): void {
    const ctx: common.UIAbilityContext | null = this.uiContext;
    if (ctx === null) {
      result.success(null);
      return;
    }
    pickImage(ctx)
      .then((photo: PickedPhoto | null) => {
        result.success(pickedMapOf(photo));
      })
      .catch((e: Object) => {
        Dlog.warn('pickImage failed: ' + JSON.stringify(e));
        const map: Map<string, Object> = new Map<string, Object>();
        map.set('error', '图片读取失败');
        result.success(map);
      });
  }

  /** 文件字节落 cacheDir → startAbility 交系统查看器。 */
  private handleOpenFile(call: MethodCall, result: MethodResult): void {
    const ctx: common.UIAbilityContext | null = this.uiContext;
    if (ctx === null) {
      result.success(false);
      return;
    }
    const args = call.args as Map<Object, Object>;
    const name: string = args.get('name') as string;
    const rawMime = args.get('mime');
    const mime: string =
      rawMime !== undefined && rawMime !== null && (rawMime as string).length > 0
        ? (rawMime as string)
        : 'application/octet-stream';
    const rawBytes = args.get('bytes');
    if (!(rawBytes instanceof Uint8Array) || name.length === 0) {
      result.success(false);
      return;
    }
    const bytes: Uint8Array = rawBytes as Uint8Array;
    // 复制成独立 ArrayBuffer（Uint8Array 可能带 offset，不能直接拿 .buffer 写）。
    const ab: ArrayBuffer = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(ab).set(bytes);
    const safeName: string = name.split('/').join('_').split('\\').join('_');
    const dest: string = ctx.cacheDir + '/open-' + Date.now().toString() + '-' + safeName;
    this.writeAndOpen(ctx, dest, ab, mime, result);
  }

  private writeAndOpen(
    ctx: common.UIAbilityContext,
    dest: string,
    ab: ArrayBuffer,
    mime: string,
    result: MethodResult
  ): void {
    const self = this;
    fs.open(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
      .then((file: fs.File) => {
        return fs.write(file.fd, ab).then(() => {
          fs.closeSync(file.fd);
          return self.startViewer(ctx, dest, mime);
        });
      })
      .then((ok: boolean) => {
        result.success(ok);
      })
      .catch((e: Object) => {
        Dlog.warn('openFile failed: ' + JSON.stringify(e));
        result.success(false);
      });
  }

  private async startViewer(
    ctx: common.UIAbilityContext,
    dest: string,
    mime: string
  ): Promise<boolean> {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: fileUri.getUriFromPath(dest),
        type: mime,
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      await ctx.startAbility(want);
      return true;
    } catch (e) {
      Dlog.warn('startAbility viewData failed: ' + JSON.stringify(e));
      return false;
    }
  }
}

/** PickedPhoto → Dart 侧约定的 Map；取消回 null。 */
function pickedMapOf(photo: PickedPhoto | null): Map<string, Object> | null {
  if (photo === null) {
    return null;
  }
  const map: Map<string, Object> = new Map<string, Object>();
  if (photo.error.length > 0) {
    map.set('error', photo.error);
    return map;
  }
  map.set('path', photo.path);
  map.set('name', photo.name);
  map.set('mediaType', photo.mediaType);
  return map;
}
