/**
 * 根路由 —— 连接流（阶段 2）：启动读凭证自动连接，失败进连接页。
 * 路由：boot（自动连接中）→ connect（连接页）→ chat（对话页）。
 */

import { GatewayClient } from '../core/GatewayClient';
import { GatewayApi } from '../core/GatewayApi';
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

@Entry
@Component
struct Index {
  @StorageProp('dshDark') dark: boolean = false;
  @State route: string = 'boot';
  @State gateway: GatewayClient | null = null;
  @State api: GatewayApi | null = null;
  @State chat: ChatStore | null = null;
  @State bootHint: string = '正在连接…';
  private mediaListener: mediaquery.MediaQueryListener | null = null;

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
    this.autoConnect();
  }

  aboutToDisappear(): void {
    if (this.mediaListener !== null) {
      this.mediaListener.off('change');
      this.mediaListener = null;
    }
  }

  /// 系统深浅色监听（窗口 API 无色模式直读，mediaquery 是官方口径）。
  private bindDarkMode(): void {
    try {
      const listener = this.getUIContext().getMediaQuery()
        .matchMediaSync('(dark-mode: true)');
      this.applyTheme(listener.matches);
      listener.on('change', (result: mediaquery.MediaQueryResult): void => {
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
    const mode: string = AppStorage.get<string>('dshThemeMode') ?? 'system';
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
      this.api = new GatewayApi(gateway, null);
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
            .width(36)
            .height(36)
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
