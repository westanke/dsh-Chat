/**
 * 设置页 —— 对照安卓 settings_page/settings_sections/settings_update：
 * 六分区（连接/外观/发送/关于/断开连接；诊断区鸿蒙首版不摆——hilog 不落
 * 文件，PORT-MAP 偏差）。字号缩放不摆（ArkUI 无 per-app fontScale，
 * 不放无法生效的开关，同安卓「不摆无法生效的开关」原则）。
 * 更新检查：查新版 + 引导跳 Gitee（鸿蒙不能自安装 APK，下载/安装不移植）。
 */

import { ChatStore } from '../core/ChatStore';
import { JsonAccess, JsonMap } from '../core/JsonAccess';
import { GatewayState } from '../core/GatewayEvents';
import { RELEASE_REPO, ReleaseInfo, fetchLatestRelease, isNewerVersion } from '../core/ReleaseCheck';
import { HttpTransport } from '../core/Transport';
import { HttpTransportImpl } from '../platform/HttpTransport';
import { appVersion, PrefsStore } from '../platform/PlatformBridge';
import { common, Want } from '@kit.AbilityKit';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

const GITEE_RELEASES_URL: string = 'https://gitee.com/' + RELEASE_REPO + '/releases';

/// 本机版本名 → 三段 number（解析失败回 [0,0,0]，不拿 0.0.0 误报）。
function localVersionParts(name: string): number[] {
  const clean: string = name.startsWith('v') ? name.substring(1) : name;
  const segs: string[] = clean.split('.');
  const out: number[] = [];
  for (let i = 0; i < 3; i++) {
    const n: number = i < segs.length ? parseInt(segs[i], 10) : 0;
    out.push(Number.isNaN(n) ? 0 : n);
  }
  return out;
}

@Component
export struct SettingsView {
  store: ChatStore | null = null;
  onDisconnect: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @StorageProp('dshThemeMode') themeMode: string = 'system';
  @StorageProp('dshBusySend') busySend: string = 'queue';
  @State versionLabel: string = '…';
  @State updateChecking: boolean = false;
  @State updateHint: string = '';
  @State updateNewTag: string = '';
  @State confirmDiscard: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
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

  private checkUpdate(silent: boolean): void {
    if (this.updateChecking) {
      return;
    }
    this.updateChecking = true;
    if (!silent) {
      this.updateHint = '正在检查（Gitee → GitHub）…';
    }
    const http: HttpTransport = new HttpTransportImpl();
    fetchLatestRelease(http).then((rel: ReleaseInfo): void => {
      this.updateChecking = false;
      const cur: string = this.versionLabel;
      const dash: number = cur.indexOf('+');
      const curName: string = dash > 0 ? cur.substring(0, dash) : cur;
      const parts: number[] = localVersionParts(curName);
      if (parts[0] === 0 && parts[1] === 0 && parts[2] === 0) {
        // 本机版本没读到，不拿 0.0.0 误报。
        this.updateHint = silent ? '' : '本机版本读取失败，无法比较';
        return;
      }
      if (isNewerVersion(rel.versionParts, parts)) {
        this.updateNewTag = rel.tag;
        this.updateHint = '发现新版本 ' + rel.tag + '，点此前往下载页';
      } else {
        this.updateNewTag = '';
        this.updateHint = silent ? '' : '已是最新版本（远端 ' + rel.tag + '）';
      }
    }).catch((): void => {
      this.updateChecking = false;
      this.updateNewTag = '';
      this.updateHint = silent ? '' : '检查失败：Gitee / GitHub 都连不上';
    });
  }

  private openReleasePage(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['ohos.want.action.entity.view'],
      uri: GITEE_RELEASES_URL
    };
    ctx.startAbility(want).catch((): void => {
    });
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column() {
          this.connectionSection()
          this.appearanceSection()
          this.sendSection()
          this.aboutSection()
          this.disconnectSection()
        }
        .width('100%')
      }
      .align(Alignment.Top)
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
        .width(40)
        .height(DsSpacing.topBarHeight)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.getUIContext().getRouter().back();
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
      Text(label)
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelSecondary)
        .layoutWeight(1)
      Text(value)
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelPrimary)
        .textAlign(TextAlign.End)
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
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
      .borderRadius(DsSpacing.chipRadius)
      .backgroundColor(this.themeMode === mode ? this.c().chipSelectedBg : this.c().inputFill)
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
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
      .borderRadius(DsSpacing.chipRadius)
      .backgroundColor(this.busySend === mode ? this.c().chipSelectedBg : this.c().inputFill)
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
      this.infoRow('版本', this.versionLabel)
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
            .fontSize(15)
            .fontColor(this.c().labelSecondary)
        }
      }
      .width('100%')
      .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
      .onClick(() => {
        if (this.updateNewTag.length > 0) {
          this.openReleasePage();
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
          .onClick(() => {
            if (this.updateNewTag.length > 0) {
              this.openReleasePage();
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

  @Builder
  disconnectSection() {
    this.sectionTitle('断开连接')
    Button('断开连接')
      .fontSize(DsTypography.smallStrong.size)
      .fontColor(this.c().danger)
      .backgroundColor(Color.Transparent)
      .borderWidth(1)
      .borderColor(this.c().danger)
      .borderRadius(DsSpacing.bubbleRadius)
      .width('100%')
      .height(44)
      .onClick(() => {
        this.confirmDiscard = true;
      })
    Text('将断开当前连接、清除本机配对并回到连接页；下次启动需重新输入配对码。')
      .fontSize(DsTypography.caption.size)
      .fontColor(this.c().labelTertiary)
      .width('100%')
      .padding({ top: DsSpacing.liGap, bottom: DsSpacing.blockGap })
    if (this.confirmDiscard) {
      this.confirmDialog()
    }
  }

  /** 断开二次确认（安卓 AlertDialog 口径）。 */
  @Builder
  confirmDialog() {
    Column()
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .backgroundColor(this.c().drawerScrim)
      .onClick(() => {
        this.confirmDiscard = false;
      })
    Column({ space: DsSpacing.blockGap }) {
      Text('断开连接？')
        .fontSize(DsTypography.h4.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
      Text('本机配对信息会被清除，下次启动需重新输入配对码。')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelSecondary)
      Row({ space: DsSpacing.blockGap }) {
        Button('取消')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelPrimary)
          .backgroundColor(this.c().inputFill)
          .layoutWeight(1)
          .onClick(() => {
            this.confirmDiscard = false;
          })
        Button('断开')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().onBrand)
          .backgroundColor(this.c().danger)
          .layoutWeight(1)
          .onClick(() => {
            this.confirmDiscard = false;
            if (this.onDisconnect !== null) {
              this.onDisconnect();
            }
          })
      }
      .width('100%')
    }
    .width('82%')
    .padding(DsSpacing.blockGap)
    .borderRadius(DsSpacing.settingsCardRadius)
    .backgroundColor(this.c().settingsSurface)
    .position({ x: '9%', y: '38%' })
  }
}
