/**
 * 通知插件 —— Flutter MethodChannel `dsh/notify`。
 *
 * 对齐安卓 MainActivity.kt 的 dsh/notify（:49）与 NotificationHelper.kt：
 *   ensureChannels / status / requestPermission / openSettings /
 *   show / cancel / cancelAll / takeLaunchTap，并支持原生回推 `tap`。
 *
 * 鸿蒙口径：
 * - 没有 Android 的「渠道」概念，用 notificationManager.addSlot(SlotType) 建槽：
 *   done → SERVICE_INFORMATION（低打扰）、attention → SOCIAL_COMMUNICATION（响铃）；
 * - 权限只有系统开关一个维度：status 的 permission/enabled 都取 isNotificationEnabled，
 *   requestPermission 走 requestEnableNotification（系统弹窗），openSettings 走
 *   openNotificationSettings；
 * - 通知点击用 WantAgent(START_ABILITY) 拉起本 Ability 并带上 key/sessionId；
 *   冷启动由 EntryAbility.onCreate → stashLaunchWant 暂存，Dart 用 takeLaunchTap 取走；
 *   已在运行时的点击由 EntryAbility.onNewWant → handleWant 直接回推 `tap`。
 */

import { common, Want, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { Dlog } from '../platform/Dlog';

/** 点击 Want 里携带的载荷字段名（与安卓 EXTRA_KEY / EXTRA_SESSION_ID 对应）。 */
const PARAM_KEY: string = 'dsh_notify_key';
const PARAM_SESSION: string = 'dsh_notify_session';

/** 冷启动时从通知点进来的载荷（Dart takeLaunchTap 取走即清）。 */
let pendingTap: Map<string, string> | null = null;

/** 从 Want 提取点击载荷；没有载荷回 null。 */
function tapOf(want: Want | null): Map<string, string> | null {
  if (want === null || want.parameters === undefined || want.parameters === null) {
    return null;
  }
  const params = want.parameters as Record<string, Object>;
  const rawKey: Object | undefined = params[PARAM_KEY];
  if (rawKey === undefined || rawKey === null) {
    return null;
  }
  const key: string = rawKey as string;
  if (key.length === 0) {
    return null;
  }
  const tap: Map<string, string> = new Map<string, string>();
  tap.set('key', key);
  const rawSession: Object | undefined = params[PARAM_SESSION];
  if (rawSession !== undefined && rawSession !== null) {
    const sessionId: string = rawSession as string;
    if (sessionId.length > 0) {
      tap.set('sessionId', sessionId);
    }
  }
  return tap;
}

/** 从 Map 参数取字符串（缺省空串）。 */
function strOf(args: Map<Object, Object>, key: string): string {
  const v: Object | undefined = args.get(key);
  if (v === undefined || v === null) {
    return '';
  }
  return v as string;
}

/** 从 Map 参数取布尔（缺省 false）。 */
function boolOf(args: Map<Object, Object>, key: string): boolean {
  const v: Object | undefined = args.get(key);
  if (v === undefined || v === null) {
    return false;
  }
  return v as boolean;
}

export default class DshNotifyPlugin implements FlutterPlugin, AbilityAware {
  /** 运行期单例：EntryAbility.onNewWant 用它回推点击。 */
  static inst: DshNotifyPlugin | null = null;

  /** 冷启动暂存 want（EntryAbility.onCreate 调）。 */
  static stashLaunchWant(want: Want | null): void {
    const tap: Map<string, string> | null = tapOf(want);
    if (tap !== null) {
      pendingTap = tap;
    }
  }

  /** 新 Want（通知点击）→ 有通道直接回推 tap，否则暂存等 Dart 取。 */
  static handleWant(want: Want | null): void {
    const tap: Map<string, string> | null = tapOf(want);
    if (tap === null) {
      return;
    }
    const inst: DshNotifyPlugin | null = DshNotifyPlugin.inst;
    if (inst !== null && inst.channel !== null) {
      const cb: MethodResult = {
        success: () => {},
        error: () => {},
        notImplemented: () => {}
      };
      inst.channel.invokeMethod('tap', tap, cb);
      return;
    }
    pendingTap = tap;
  }

  private channel: MethodChannel | null = null;
  private uiContext: common.UIAbilityContext | null = null;
  /** 通知 key → 通知 id（同 key 原地替换；cancel 按 key 找回 id）。 */
  private ids: Map<string, number> = new Map<string, number>();
  /** id 占位表（防 hash 撞车覆盖别人的通知）。 */
  private usedIds: Map<number, string> = new Map<number, string>();

  getUniqueClassName(): string {
    return 'DshNotifyPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    DshNotifyPlugin.inst = this;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'dsh/notify');
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
    if (DshNotifyPlugin.inst === this) {
      DshNotifyPlugin.inst = null;
    }
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
      case 'ensureChannels':
        ensureSlots()
          .then(() => {
            result.success(null);
          })
          .catch((e: Object) => {
            Dlog.warn('ensureChannels failed: ' + JSON.stringify(e));
            result.success(null);
          });
        break;
      case 'status':
        this.reportStatus(result);
        break;
      case 'requestPermission':
        this.requestPermission(result);
        break;
      case 'openSettings':
        this.openSettings(result);
        break;
      case 'show':
        this.show(call.args as Map<Object, Object>, result);
        break;
      case 'cancel':
        this.cancel(call.args as Map<Object, Object>);
        result.success(null);
        break;
      case 'cancelAll':
        notificationManager.cancelAll().catch((e: Object) => {
          Dlog.warn('cancelAll failed: ' + JSON.stringify(e));
        });
        result.success(null);
        break;
      case 'takeLaunchTap': {
        const tap: Map<string, string> | null = pendingTap;
        pendingTap = null;
        result.success(tap);
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }

  /** {permission, enabled}：鸿蒙只有一个系统开关，两者同值。 */
  private reportStatus(result: MethodResult): void {
    let enabled: boolean = false;
    try {
      enabled = notificationManager.isNotificationEnabledSync();
    } catch (e) {
      Dlog.warn('isNotificationEnabledSync failed: ' + JSON.stringify(e));
    }
    const map: Map<string, Object> = new Map<string, Object>();
    map.set('permission', enabled);
    map.set('enabled', enabled);
    result.success(map);
  }

  private requestPermission(result: MethodResult): void {
    const ctx: common.UIAbilityContext | null = this.uiContext;
    if (ctx === null) {
      result.success(false);
      return;
    }
    notificationManager
      .requestEnableNotification(ctx)
      .then(() => {
        this.reportEnabled(result);
      })
      .catch((e: Object) => {
        Dlog.warn('requestEnableNotification failed: ' + JSON.stringify(e));
        this.reportEnabled(result);
      });
  }

  private reportEnabled(result: MethodResult): void {
    let enabled: boolean = false;
    try {
      enabled = notificationManager.isNotificationEnabledSync();
    } catch (e) {
      Dlog.warn('isNotificationEnabledSync failed: ' + JSON.stringify(e));
    }
    result.success(enabled);
  }

  private openSettings(result: MethodResult): void {
    const ctx: common.UIAbilityContext | null = this.uiContext;
    if (ctx === null) {
      result.success(null);
      return;
    }
    notificationManager.openNotificationSettings(ctx).catch((e: Object) => {
      Dlog.warn('openNotificationSettings failed: ' + JSON.stringify(e));
    });
    result.success(null);
  }

  private show(args: Map<Object, Object>, result: MethodResult): void {
    const key: string = strOf(args, 'key');
    const title: string = strOf(args, 'title');
    const text: string = strOf(args, 'text');
    const sessionId: string = strOf(args, 'sessionId');
    const attention: boolean = boolOf(args, 'attention');
    if (key.length === 0 || title.length === 0) {
      result.success(false);
      return;
    }
    const ctx: common.UIAbilityContext | null = this.uiContext;
    if (ctx === null) {
      result.success(false);
      return;
    }
    let enabled: boolean = false;
    try {
      enabled = notificationManager.isNotificationEnabledSync();
    } catch (e) {
      Dlog.warn('isNotificationEnabledSync failed: ' + JSON.stringify(e));
    }
    if (!enabled) {
      result.success(false);
      return;
    }
    const id: number = this.idOf(key);
    this.publish(ctx, id, title, text, sessionId, key, attention)
      .then((ok: boolean) => {
        result.success(ok);
      })
      .catch((e: Object) => {
        Dlog.warn('publish failed: ' + JSON.stringify(e));
        result.success(false);
      });
  }

  private async publish(
    ctx: common.UIAbilityContext,
    id: number,
    title: string,
    text: string,
    sessionId: string,
    key: string,
    attention: boolean
  ): Promise<boolean> {
    await ensureSlots();
    const parameters: Record<string, Object> = {};
    parameters[PARAM_KEY] = key;
    if (sessionId.length > 0) {
      parameters[PARAM_SESSION] = sessionId;
    }
    const want: Want = {
      bundleName: ctx.abilityInfo.bundleName,
      abilityName: ctx.abilityInfo.name,
      parameters: parameters
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: id,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    const agent = await wantAgent.getWantAgent(info);
    const content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: title,
        text: text
      }
    };
    const request: notificationManager.NotificationRequest = {
      id: id,
      content: content,
      notificationSlotType: attention
        ? notificationManager.SlotType.SOCIAL_COMMUNICATION
        : notificationManager.SlotType.SERVICE_INFORMATION,
      wantAgent: agent,
      tapDismissed: true
    };
    await notificationManager.publish(request);
    return true;
  }

  private cancel(args: Map<Object, Object>): void {
    const key: string = strOf(args, 'key');
    if (key.length === 0) {
      return;
    }
    const id: number | undefined = this.ids.get(key);
    if (id === undefined) {
      return;
    }
    notificationManager.cancel(id).catch((e: Object) => {
      Dlog.warn('cancel failed: ' + JSON.stringify(e));
    });
    this.ids.delete(key);
    this.usedIds.delete(id);
  }

  /** 稳定 id：同一 key 永远同一 id（应用重启后仍能覆盖/取消）。 */
  private idOf(key: string): number {
    const existing: number | undefined = this.ids.get(key);
    if (existing !== undefined) {
      return existing;
    }
    let h: number = 5381;
    for (let i = 0; i < key.length; i++) {
      h = ((h * 33) ^ key.charCodeAt(i)) & 0x7fffffff;
    }
    let id: number = (h % 2000000000) + 1;
    while (this.usedIds.has(id) && this.usedIds.get(id) !== key) {
      id = id >= 2000000000 ? 1 : id + 1;
    }
    this.ids.set(key, id);
    this.usedIds.set(id, key);
    return id;
  }
}

/** 建两档通知槽（幂等；已存在时的错误忽略）。 */
async function ensureSlots(): Promise<void> {
  try {
    await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
  } catch (e) {
    // 槽已存在/不支持：忽略。
  }
  try {
    await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
  } catch (e) {
    // 同上。
  }
}
