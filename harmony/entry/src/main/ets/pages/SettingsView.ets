/**
 * 设置页 —— 对照安卓 settings_page/settings_sections/settings_update：
 * 六分区（连接/外观/发送/关于/断开连接；诊断区鸿蒙首版不摆——hilog 不落
 * 文件，PORT-MAP 偏差）。字号缩放不摆（ArkUI 无 per-app fontScale，
 * 不放无法生效的开关，同安卓「不摆无法生效的开关」原则）。
 * 更新检查：走华为应用市场（AppGallery Kit `updateManager`）——
 * 鸿蒙应用只能由 AppGallery 分发，不允许自更新（用户 2026-11-16 要求
 * 从 Gitee 改为应用市场口径）。查新版 → 系统弹官方更新对话框。
 */

import { ChatStore } from '../core/ChatStore';
import { JsonAccess, JsonMap } from '../core/JsonAccess';
import { GatewayState } from '../core/GatewayEvents';
import {
  NOT_SUPPORTED_MESSAGE, UPDATE_AVAILABLE_YES, UpdateCheckResult,
} from '../core/AppUpdate';
import { appVersion, PrefsStore } from '../platform/PlatformBridge';
import { common } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { mediaquery } from '@kit.ArkUI';
import { BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd,
  contentMaxWidth } from '../core/Breakpoints';
import { SettingsGeneralSection } from '../components/SettingsGeneralSection';
import { SettingsDisconnectSection } from '../components/SettingsDisconnectSection';


@Component
export struct SettingsView {
  /** 窗口宽度断点（R007 一多）：返回键行高按档放大。 */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;
  store: ChatStore | null = null;
  onDisconnect: (() => void) | null = null;
  /** 返回对话页（Index 用 @State route 切页，不是 Router 栈，不能 back()）。 */
  onBack: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @StorageProp('dshThemeMode') themeMode: string = 'system';
  @StorageProp('dshBusySend') busySend: string = 'queue';
  @State versionLabel: string = '…';
  @State updateChecking: boolean = false;
  @State updateHint: string = '';
  @State updateNewTag: string = '';

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** 窗口断点自读（R007 一多）：返回键与标题行在宽屏加高。 */
  private refreshBreakpoint(): void {
    try {
      const md: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_MD);
      const lg: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_LG);
      const next: string = breakpointOf(md.matches, lg.matches);
      if (next !== this.bp) {
        this.bp = next;
        AppStorage.setOrCreate('dshBreakpoint', next);
      }
    } catch (e) {
      // 拿不到 mediaquery 时按手机档渲染，不阻塞页面。
    }
  }

  private atLeastMd(): boolean {
    return atLeastMd(this.bp);
  }

  aboutToAppear(): void {
    this.refreshBreakpoint();
    appVersion().then((v: string): void => {
      this.versionLabel = v;
    }).catch((): void => {
      this.versionLabel = '…';
    });
    // 静默检查一次（安卓 1.5s 延迟口径；只在有新版时提示）。
    setTimeout((): void => {
      this.checkUpdate(true);
    }, 1500);
  }

  private connected(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.connectionState === GatewayState.READY;
  }

  private stateLabel(): string {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return '未连接';
    }
    const s: GatewayState = st.connectionState;
    if (s === GatewayState.CONNECTING) {
      return '连接中';
    }
    if (s === GatewayState.READY) {
      return '已连接';
    }
    if (s === GatewayState.CLOSED) {
      return '已断开';
    }
    return '未连接';
  }

  private deviceLine(): string {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return '设备 ID 未提供';
    }
    const dev: JsonMap | null = st.getServerDevice();
    const name: string = JsonAccess.strOr(dev, 'name', '');
    const id: string = JsonAccess.strOr(dev, 'id', '');
    if (name.length === 0 && id.length === 0) {
      return '设备 ID 未提供';
    }
    if (name.length > 0 && id.length > 0) {
      return name + ' · ' + id;
    }
    return name.length > 0 ? name : id;
  }

  /**
   * 检查更新 —— 走 AppGallery Kit（华为应用市场）。
   * silent=true 时（进设置页自动）不显示「检查中/最新」文案，保持安静。
   */
  private checkUpdate(silent: boolean): void {
    if (this.updateChecking) {
      return;
    }
    this.updateChecking = true;
    if (!silent) {
      this.updateHint = '正在向华为应用市场查询…';
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    updateManager.checkAppUpdate(ctx).then((res: updateManager.CheckUpdateResult): void => {
      this.updateChecking = false;
      if (res.updateAvailable === UPDATE_AVAILABLE_YES) {
        this.updateHint = UpdateCheckResult.ofNew().message;
        this.updateNewTag = 'new';
      } else {
        this.updateNewTag = '';
        this.updateHint = silent ? '' : UpdateCheckResult.ofLatest().message;
      }
    }).catch((e: BusinessError): void => {
      this.updateChecking = false;
      this.updateNewTag = '';
      const code: string = e !== null && e.code !== undefined ? e.code.toString() : '';
      // 能力不可用（开发者预览版系统 / 非市场安装）不当作错误刷屏。
      if (code === '1009400007' || code === '1009400001') {
        this.updateHint = silent ? '' : NOT_SUPPORTED_MESSAGE;
        return;
      }
      this.updateHint = silent ? '' : UpdateCheckResult.ofError(code, e.message ?? '').message;
    });
  }

  /** 有新版时点「检查更新」→ 系统弹官方更新对话框（升级在应用市场完成）。 */
  private showUpdateDialog(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    updateManager.showUpdateDialog(ctx).then((code: updateManager.ShowUpdateResultCode): void => {
      if (code !== updateManager.ShowUpdateResultCode.SHOW_DIALOG_SUCCESS) {
        this.updateHint = '打开更新对话框失败，请到华为应用市场手动更新';
      }
    }).catch((e: BusinessError): void => {
      const msg: string = e !== null && e.message !== undefined && e.message !== '' ? e.message : '';
      this.updateHint = '打开应用市场失败' + (msg.length > 0 ? ('：' + msg) : '');
    });
  }


  build() {
    Column() {
      this.header()
      Scroll() {
        // 外层只负责一多居中：超宽屏内容列封顶 settingsMaxWidth 后左右留白。
        Column() {
          Column() {
            this.connectionSection()
            this.appearanceSection()
            SettingsGeneralSection()
            this.sendSection()
            this.aboutSection()
            SettingsDisconnectSection({ onDisconnect: this.onDisconnect })
          }
          .width('100%')
          // 页面级根边距（安卓 settingsPadH/V 口径，鸿蒙按触屏边缘余量微调）：
          // 卡片之间靠 sectionTitle 的上间距拉分区间距，卡片自己只有
          // settingsCardPadH/V 内边距。
          .padding({ left: DsSpacing.settingsPadH, right: DsSpacing.settingsPadH,
            top: DsSpacing.settingsPadV, bottom: DsSpacing.settingsPadV })
          .constraintSize({ maxWidth: contentMaxWidth(this.bp) > 0
            ? contentMaxWidth(this.bp) : DsSpacing.settingsMaxWidth })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c().bgBase)
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Text('‹')
        .fontSize(24)
        .fontColor(this.c().labelPrimary)
        .width(this.atLeastMd() ? 48 : 40)
        .height(this.atLeastMd() ? DsSpacing.topBarHeight + 8 : DsSpacing.topBarHeight)
        .textAlign(TextAlign.Center)
        .accessibilityText('返回')
        .onClick(() => {
          if (this.onBack !== null) {
            this.onBack();
          }
        })
      Text('设置')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c().labelPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(DsSpacing.topBarHeight)
    .padding({ left: DsSpacing.screenPad - 14, right: DsSpacing.screenPad - 14 })
  }

  @Builder
  sectionTitle(t: string) {
    Text(t)
      .fontSize(DsTypography.caption.size)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.c().drawerGroupLabel)
      .width('100%')
      .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.liGap })
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      // label 给固定最小宽并单行省略：长值（设备 ID 一整串 UUID）不再把
      // 「设备」两个字挤成竖排（真机 2026-11-17 反馈「超屏幕/换行错位」）。
      Text(label)
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelSecondary)
        .width(DsSpacing.settingsLabelWidth)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // value 占剩余宽并允许换行（官方「该换行的换行」口径）。
      Text(value)
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelPrimary)
        .textAlign(TextAlign.End)
        .layoutWeight(1)
        .wordBreak(WordBreak.BREAK_ALL)
    }
    .width('100%')
    .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
  }

  @Builder
  connectionSection() {
    this.sectionTitle('连接')
    Column() {
      if (!this.connected()) {
        Text('🔌 配对后此处显示设备与授权信息')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelSecondary)
          .width('100%')
      } else {
        this.infoRow('状态', this.stateLabel())
        this.infoRow('设备', this.deviceLine())
      }
    }
    .width('100%')
    .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
      top: DsSpacing.settingsCardPadV, bottom: DsSpacing.settingsCardPadV })
    .borderRadius(DsSpacing.settingsCardRadius)
    .backgroundColor(this.c().settingsSurface)
    Text('服务端的命名空间、模型与 provider 设置走 REST /api/v1/settings/*，写入需要 '
      + 'settings.write 授权（设备默认不含）。本页只提供本地偏好，不摆无法生效的开关。')
      .fontSize(DsTypography.caption.size)
      .fontColor(this.c().labelTertiary)
      .width('100%')
      .padding({ top: DsSpacing.liGap })
  }

  /** 界面风格三选（跟随系统/浅色/深色；写 dshThemeMode，Index 统一落深浅色）。 */
  @Builder
  appearanceSection() {
    this.sectionTitle('外观')
    Column() {
      Text('界面风格')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelPrimary)
        .width('100%')
        .padding({ bottom: DsSpacing.liGap })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.themeChip('system', '跟随系统')
        this.themeChip('light', '浅色')
        this.themeChip('dark', '深色')
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
      top: DsSpacing.settingsCardPadV, bottom: DsSpacing.settingsCardPadV })
    .borderRadius(DsSpacing.settingsCardRadius)
    .backgroundColor(this.c().settingsSurface)
  }

  @Builder
  themeChip(mode: string, label: string) {
    Text(label)
      .fontSize(DsTypography.caption.size)
      .fontColor(this.themeMode === mode ? this.c().chipSelectedFg : this.c().labelSecondary)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
      .borderRadius(DsSpacing.chipRadius)
      .backgroundColor(this.themeMode === mode ? this.c().chipSelectedBg : this.c().inputFill)
      .accessibilityText(label)
      .onClick(() => {
        AppStorage.setOrCreate('dshThemeMode', mode);
        PrefsStore.putString('dsh.themeMode', mode);
      })
  }

  /** 繁忙时发送模式（queue 排队 / steer 插话；发消息时由 Composer 读取）。 */
  @Builder
  sendSection() {
    this.sectionTitle('发送')
    Column() {
      Text('运行中再发消息')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelPrimary)
        .width('100%')
        .padding({ bottom: DsSpacing.liGap })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.sendChip('queue', '排队')
        this.sendChip('steer', '插话')
      }
      .width('100%')
      Text('排队=当前回合结束后处理；插话=立即打断当前回合。')
        .fontSize(DsTypography.caption.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
        .padding({ top: DsSpacing.liGap })
    }
    .width('100%')
    .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
      top: DsSpacing.settingsCardPadV, bottom: DsSpacing.settingsCardPadV })
    .borderRadius(DsSpacing.settingsCardRadius)
    .backgroundColor(this.c().settingsSurface)
  }

  @Builder
  sendChip(mode: string, label: string) {
    Text(label)
      .fontSize(DsTypography.caption.size)
      .fontColor(this.busySend === mode ? this.c().chipSelectedFg : this.c().labelSecondary)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
      .borderRadius(DsSpacing.chipRadius)
      .backgroundColor(this.busySend === mode ? this.c().chipSelectedBg : this.c().inputFill)
      .accessibilityText(label)
      .onClick(() => {
        AppStorage.setOrCreate('dshBusySend', mode);
        PrefsStore.putString('dsh.busySend', mode);
      })
  }

  @Builder
  aboutSection() {
    this.sectionTitle('关于')
    Column() {
      this.infoRow('DSH Chat', 'HarmonyOS client for dsh-remote-bridge')
      // 版本行必须内联：@Builder 按值传参（这里是字面量+@State 两参），
      // versionLabel 异步就绪后不会重算，会永远停在初始 '…'（真机实证）。
      Row() {
        Text('版本')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelSecondary)
          .layoutWeight(1)
        Text(this.versionLabel)
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelPrimary)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
      Row() {
        Text('检查更新')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelPrimary)
          .layoutWeight(1)
        if (this.updateChecking) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.c().labelSecondary)
        } else {
          Text(this.updateNewTag.length > 0 ? '↗' : '⟳')
            .fontSize(16)
            .fontColor(this.c().labelSecondary)
        }
      }
      .width('100%')
      .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
      .accessibilityText('检查更新')
      .onClick(() => {
        if (this.updateNewTag.length > 0) {
          this.showUpdateDialog();
        } else {
          this.checkUpdate(false);
        }
      })
      if (this.updateHint.length > 0) {
        Text(this.updateHint)
          .fontSize(DsTypography.caption.size)
          .fontColor(this.updateNewTag.length > 0 ? this.c().brand : this.c().labelTertiary)
          .width('100%')
          .padding({ bottom: DsSpacing.liGap })
          .accessibilityText('检查更新')
          .onClick(() => {
            if (this.updateNewTag.length > 0) {
              this.showUpdateDialog();
            }
          })
      }
      this.infoRow('协议', 'dsh-mobile-v1 · protocol 3')
    }
    .width('100%')
    .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
      top: DsSpacing.settingsCardPadV, bottom: DsSpacing.settingsCardPadV })
    .borderRadius(DsSpacing.settingsCardRadius)
    .backgroundColor(this.c().settingsSurface)
  }

}
