/**
 * 根路由 —— 连接流（阶段 2）：启动读凭证自动连接，失败进连接页。
 * 路由：boot（自动连接中）→ connect（连接页）→ chat（对话页）。
 */

import { GatewayClient } from '../core/GatewayClient';
import { GatewayApi } from '../core/GatewayApi';
import { HttpTransportImpl } from '../platform/HttpTransport';
import { GatewayDeps } from '../core/GatewayClient';
import { DshCredentials, CREDENTIALS_STORAGE_KEY } from '../core/Credentials';
import { WsTransport } from '../platform/WsTransport';
import { ArkTimers, timeZoneId, PrefsStore } from '../platform/PlatformBridge';
import { Dlog } from '../platform/Dlog';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { mediaquery } from '@kit.ArkUI';
import { ConnectView } from './ConnectView';
import { ChatView } from './ChatView';
import { SettingsView } from './SettingsView';
import { ChatStore } from '../core/ChatStore';
import {
  BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf,
} from '../core/Breakpoints';

@Entry
@Component
struct Index {
  @StorageProp('dshDark') dark: boolean = false;
  /// 界面风格偏好（system/light/dark）：设置页写入后这里 @Watch 重算 dshDark。
  @StorageProp('dshThemeMode') @Watch('onThemeModeChange') themeMode: string = 'system';
  @State route: string = 'boot';
  @State gateway: GatewayClient | null = null;
  @State api: GatewayApi | null = null;
  @State chat: ChatStore | null = null;
  @State bootHint: string = '正在连接…';
  /**
   * 窗口宽度断点（R007）：<600vp=sm / 600–840=md / ≥840=lg。
   * 写 AppStorage 供 ChatView / SessionsDrawer / 各面板用 @StorageProp 读。
   */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;
  private mediaListener: mediaquery.MediaQueryListener | null = null;
  private bpMd: mediaquery.MediaQueryListener | null = null;
  private bpLg: mediaquery.MediaQueryListener | null = null;
  /// 系统深浅色（mediaquery 最近一次结果），手动切档时以它为基准。
  private sysDark: boolean = false;

  /** ChatStore 单例：同一条连接上换页不重建（状态保留）。 */
  private chatStore(): ChatStore {
    if (this.chat === null && this.gateway !== null && this.api !== null) {
      this.chat = new ChatStore(this.gateway, this.api, new ArkTimers());
    }
    return this.chat as ChatStore;
  }

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.bindDarkMode();
    this.bindBreakpoints();
    // 偏好是异步读的（PrefsStore.getString 返 Promise），回来后重算一次配色。
    PrefsStore.getString('dsh.themeMode').then((saved: string | null): void => {
      const mode: string = saved !== null && saved !== '' ? saved : 'system';
      AppStorage.setOrCreate('dshThemeMode', mode);
      this.themeMode = mode;
      this.applyTheme(this.sysDark);
    }).catch((): void => {
    });
    this.autoConnect();
  }

  /// 设置页切换界面风格 → 立刻重算生效（只写 AppStorage 不会自动触发）。
  onThemeModeChange(): void {
    this.applyTheme(this.sysDark);
  }

  aboutToDisappear(): void {
    if (this.mediaListener !== null) {
      this.mediaListener.off('change');
      this.mediaListener = null;
    }
    if (this.bpMd !== null) {
      this.bpMd.off('change');
      this.bpMd = null;
    }
    if (this.bpLg !== null) {
      this.bpLg.off('change');
      this.bpLg = null;
    }
  }

  /**
   * 窗口宽度断点监听（R007）。用两个 mediaquery 而不是算 vp：窗口尺寸 API 在
   * 分屏/折叠态下与 mediaquery 口径偶有偏差，官方推荐 mediaquery。
   */
  private bindBreakpoints(): void {
    try {
      const md = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_MD);
      const lg = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_LG);
      AppStorage.setOrCreate('dshBreakpoint', breakpointOf(md.matches, lg.matches));
      md.on('change', (result: mediaquery.MediaQueryResult): void => {
        const curLg: mediaquery.MediaQueryListener | null = this.bpLg;
        this.bp = breakpointOf(result.matches, curLg === null ? false : curLg.matches);
        AppStorage.setOrCreate('dshBreakpoint', this.bp);
      });
      lg.on('change', (result: mediaquery.MediaQueryResult): void => {
        const curMd: mediaquery.MediaQueryListener | null = this.bpMd;
        this.bp = breakpointOf(curMd === null ? false : curMd.matches, result.matches);
        AppStorage.setOrCreate('dshBreakpoint', this.bp);
      });
      this.bpMd = md;
      this.bpLg = lg;
    } catch (e) {
      // 拿不到窗口尺寸就按紧凑档走：手机是主目标形态，退化不影响可用性。
      const err = e as Error;
      Dlog.warn('bind breakpoints failed: ' + err.message);
    }
  }

  /// 系统深浅色监听（窗口 API 无色模式直读，mediaquery 是官方口径）。
  private bindDarkMode(): void {
    try {
      const listener = this.getUIContext().getMediaQuery()
        .matchMediaSync('(dark-mode: true)');
      this.sysDark = listener.matches;
      this.applyTheme(listener.matches);
      listener.on('change', (result: mediaquery.MediaQueryResult): void => {
        this.sysDark = result.matches;
        this.applyTheme(result.matches);
      });
      this.mediaListener = listener;
    } catch (e) {
      const err = e as Error;
      Dlog.warn('bind dark mode failed: ' + err.message);
    }
  }

  /** 界面风格偏好落色：system 跟随系统，light/dark 直写（设置页写 dshThemeMode）。 */
  private applyTheme(sysDark: boolean): void {
    const mode: string = AppStorage.get<string>('dshThemeMode') ?? this.themeMode;
    let dark: boolean = sysDark;
    if (mode === 'light') {
      dark = false;
    } else if (mode === 'dark') {
      dark = true;
    }
    AppStorage.setOrCreate('dshDark', dark);
  }

  private buildGateway(baseUrl: string): GatewayClient {
    const deps: GatewayDeps = {
      ws: new WsTransport(),
      timers: new ArkTimers(),
      timeZoneId: (): string => {
        return timeZoneId();
      },
      // 真机排障出口：连接状态机打点（hilog 域 0xD5C0 / TAG Dsh）。
      trace: (message: string): void => {
        Dlog.info('[gw] ' + message);
      },
    };
    return new GatewayClient(baseUrl, deps);
  }

  /// 「一次配对，此后自动连接」：启动读凭证直连，任何失败进连接页。
  private autoConnect(): void {
    PrefsStore.getString(CREDENTIALS_STORAGE_KEY).then((raw: string | null): void => {
      if (raw === null) {
        this.route = 'connect';
        return;
      }
      const cred = DshCredentials.decode(raw);
      if (cred === null || !cred.isComplete) {
        PrefsStore.removeKey(CREDENTIALS_STORAGE_KEY).catch((e: Error): void => {
          Dlog.warn('clear credentials failed: ' + e.message);
        });
        this.route = 'connect';
        return;
      }
      const gateway = this.buildGateway(cred.baseUrl);
      gateway.setToken(cred.token, 'DSH Chat');
      this.gateway = gateway;
      // HTTP 传输必须注入：附件/图片交接/根列表/文件全文/挂起项查询全走 REST，
      // 传 null 会让这些功能在自动连接路径下全部 NO_TRANSPORT（真机踩过）。
      this.api = new GatewayApi(gateway, new HttpTransportImpl());
      this.bootHint = '正在连接 ' + cred.baseUrl;
      gateway.connect().then((): void => {
        this.route = 'chat';
      }).catch((err: Error): void => {
        Dlog.warn('auto connect failed: ' + err.message);
        gateway.dispose();
        this.gateway = null;
        this.api = null;
        this.route = 'connect';
      });
    }).catch((e: Error): void => {
      Dlog.warn('read credentials failed: ' + e.message);
      this.route = 'connect';
    });
  }

  build() {
    Stack() {
      if (this.route === 'boot') {
        Column({ space: 16 }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.c().brand)
          Text(this.bootHint)
            .fontSize(14)
            .fontColor(this.c().labelSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.c().bgBase)
      }
      if (this.route === 'connect') {
        ConnectView({
          onReady: (gateway: GatewayClient, api: GatewayApi,
            baseUrl: string, token: string): void => {
            this.gateway = gateway;
            this.api = api;
            this.route = 'chat';
          },
        })
      }
      if (this.route === 'chat') {
        ChatView({
          store: this.chatStore(), onExit: (): void => {
            // 退出到连接页（断开当前 gateway）。
            if (this.gateway !== null) {
              this.gateway.dispose();
            }
            this.gateway = null;
            this.api = null;
            this.chat = null;
            this.route = 'connect';
          }, onOpenSettings: (): void => {
            this.route = 'settings';
          },
        })
      }
      if (this.route === 'settings') {
        SettingsView({
          store: this.chatStore(), onBack: (): void => {
            this.route = 'chat';
          }, onDisconnect: (): void => {
            // 清凭证 + 断开 + 回连接页（安卓 settings 断开口径）。
            PrefsStore.removeKey('dsh.credentials');
            if (this.gateway !== null) {
              this.gateway.dispose();
            }
            this.gateway = null;
            this.api = null;
            this.chat = null;
            this.route = 'connect';
          },
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
