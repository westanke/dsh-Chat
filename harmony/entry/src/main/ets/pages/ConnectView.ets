/**
 * 连接页 —— 安卓 app/lib/ui/connect_page.dart 的 ArkUI 对应。
 * 三级路径：历史主机直连 / DSH1 配置导入 / 手动配对（REST exchange）。
 * 输入区、错误条、删除入口的口径全部对齐安卓版。
 */

import { GatewayClient, GatewayDeps } from '../core/GatewayClient';
import { GatewayApi } from '../core/GatewayApi';
import { RequestException } from '../core/GatewayEvents';
import { DshCredentials, CREDENTIALS_STORAGE_KEY } from '../core/Credentials';
import {
  DshHost, decodeDsh1, upsertHost, removeHost,
  parseHosts, encodeHosts, HOSTS_STORAGE_KEY,
} from '../core/Hosts';
import { WsTransport } from '../platform/WsTransport';
import { HttpTransportImpl } from '../platform/HttpTransport';
import {
  ArkTimers, timeZoneId, PrefsStore,
} from '../platform/PlatformBridge';
import { Dlog } from '../platform/Dlog';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

/// 就绪回调：连接成功（配对或直连）后把活的 gateway 交回宿主路由。
type ReadyCallback = (gateway: GatewayClient, api: GatewayApi,
  baseUrl: string, token: string) => void;

const DEVICE_NAME: string = 'DSH Chat';

/// 稳定错误码 → 中文提示（没有映射的原样透出 message）。
function friendlyError(code: string, message: string): string {
  if (code === 'CONNECT_FAIL') {
    return '无法连接到桥，请检查地址与网络';
  }
  if (code === 'TIMEOUT') {
    return '连接超时，请确认桥正在运行';
  }
  if (code === 'PROTOCOL') {
    return '桥协议版本不匹配，请升级桥后再试';
  }
  if (code.startsWith('HTTP_')) {
    return '桥返回错误（' + code + '），配对码可能已失效';
  }
  return message.length > 0 ? message : code;
}

@Component
export struct ConnectView {
  onReady: ReadyCallback = (gateway: GatewayClient, api: GatewayApi,
    baseUrl: string, token: string): void => {
  };
  @StorageProp('dshDark') dark: boolean = false;
  @State hosts: DshHost[] = [];
  @State urlText: string = '';
  @State pairCode: string = '';
  @State importText: string = '';
  @State importOpen: boolean = false;
  @State error: string = '';
  @State failedHostId: string = '';
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.reloadHosts();
  }

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private reloadHosts(): void {
    PrefsStore.getString(HOSTS_STORAGE_KEY).then((raw: string | null): void => {
      this.hosts = raw === null ? [] : parseHosts(raw);
    }).catch((e: Error): void => {
      Dlog.warn('load hosts failed: ' + e.message);
    });
  }

  private persistHosts(next: DshHost[]): void {
    this.hosts = next;
    PrefsStore.putString(HOSTS_STORAGE_KEY, encodeHosts(next))
      .catch((e: Error): void => {
        Dlog.warn('save hosts failed: ' + e.message);
      });
  }

  /** 归一化地址：无 scheme 补 http://，去尾斜杠。 */
  private normalizeUrl(text: string): string {
    let url = text.trim();
    if (url.length === 0) {
      return '';
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://' + url;
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  private describeError(err: Error): string {
    if (err instanceof RequestException) {
      return friendlyError(err.code, err.message);
    }
    return err.message;
  }

  /** 建客户端（未带令牌；配对成功或直连时再 setToken）。 */
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

  /** 凭证 + 主机记录 + 上报就绪（安卓 _enterWith 同口径）。 */
  private enterWith(gateway: GatewayClient, baseUrl: string, token: string): void {
    const credentials = new DshCredentials(baseUrl, token);
    PrefsStore.putString(CREDENTIALS_STORAGE_KEY, credentials.encode())
      .catch((e: Error): void => {
        Dlog.warn('save credentials failed: ' + e.message);
      });
    const host: DshHost = new DshHost();
    host.baseUrl = baseUrl;
    host.token = token;
    host.displayName = 'DSH Bridge';
    host.lastUsedAt = Date.now();
    host.id = '';
    const api = new GatewayApi(gateway, new HttpTransportImpl());
    this.onReady(gateway, api, baseUrl, token);
    this.busy = false;
  }

  /// 直连历史主机（只显示存了 token 的记录）。
  private connectHost(host: DshHost): void {
    if (host.token === null || this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.failedHostId = '';
    const gateway = this.buildGateway(host.baseUrl);
    gateway.setToken(host.token, DEVICE_NAME);
    gateway.connect().then((): void => {
      this.enterWith(gateway, host.baseUrl, host.token === null ? '' : host.token);
    }).catch((err: Error): void => {
      this.busy = false;
      gateway.dispose();
      this.error = this.describeError(err);
      this.failedHostId = host.id;
    });
  }

  /// 手动配对（REST exchange 拿 token 再走 WS 鉴权）。
  private pairAndConnect(): void {
    const url = this.normalizeUrl(this.urlText);
    const code = this.pairCode.trim();
    if (url.length === 0 || code.length === 0 || this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.failedHostId = '';
    const gateway = this.buildGateway(url);
    const api = new GatewayApi(gateway, new HttpTransportImpl());
    api.pairViaRest(code, DEVICE_NAME).then((resp: Record<string, Object>): Promise<void> => {
      const token: string | null = resp['token'] === undefined
        ? null : String(resp['token']);
      if (token === null || token.length === 0) {
        return Promise.reject(new RequestException('BAD_REPLY', '配对响应缺少令牌'));
      }
      gateway.setToken(token, DEVICE_NAME);
      return gateway.connect();
    }).then((): void => {
      const token: string | null = gateway.getToken();
      this.enterWith(gateway, url, token === null ? '' : token);
    }).catch((err: Error): void => {
      this.busy = false;
      gateway.dispose();
      this.error = this.describeError(err);
    });
  }

  /// 导入 DSH1 配置：带 token 直连，否则填进手动表单。
  private importConfig(): void {
    const host = decodeDsh1(this.importText, Date.now());
    if (host === null || host.baseUrl.length === 0) {
      this.error = '配置文本无法识别，请检查是否完整';
      return;
    }
    if (host.token !== null && host.token.length > 0) {
      this.connectHost(host);
      return;
    }
    this.urlText = host.baseUrl;
    this.pairCode = '';
    this.importText = '';
    this.importOpen = false;
    this.error = '配置里没有令牌，请输入配对码完成配对';
  }

  /// 删除主机（二次确认；删的是当前凭证地址时顺手清凭证）。
  private deleteHost(host: DshHost): void {
    this.getUIContext().showAlertDialog({
      title: '删除这条主机记录？',
      message: host.baseUrl,
      primaryButton: {
        value: '取消',
        action: (): void => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.c().danger,
        action: (): void => {
          this.persistHosts(removeHost(this.hosts, host));
          PrefsStore.getString(CREDENTIALS_STORAGE_KEY).then((raw: string | null): void => {
            if (raw !== null) {
              const cred = DshCredentials.decode(raw);
              if (cred !== null && cred.baseUrl === host.baseUrl) {
                PrefsStore.removeKey(CREDENTIALS_STORAGE_KEY).catch((e: Error): void => {
                  Dlog.warn('clear credentials failed: ' + e.message);
                });
              }
            }
          }).catch((e: Error): void => {
            Dlog.warn('read credentials failed: ' + e.message);
          });
        },
      },
    });
  }

  build() {
    Scroll() {
      Column({ space: DsSpacing.blockGap }) {
      Text('连接到 DSH Bridge')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c().labelPrimary)
      Text('一次配对，此后自动连接')
        .fontSize(14)
        .fontColor(this.c().labelSecondary)

      if (this.hosts.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.hosts, (host: DshHost) => {
            if (host.token !== null) {
              Row() {
                Column({ space: 2 }) {
                  Text(host.displayName.length > 0 ? host.displayName : host.baseUrl)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.c().labelPrimary)
                  Text(host.baseUrl)
                    .fontSize(13)
                    .fontColor(this.c().labelSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text('删除')
                  .fontSize(13)
                  .fontColor(this.c().danger)
                  .padding({ left: 12, right: 4, top: 8, bottom: 8 })
                  .onClick((): void => {
                    this.deleteHost(host);
                  })
              }
              .width('100%')
              .padding({ left: 14, right: 8, top: 10, bottom: 10 })
              .borderRadius(12)
              .backgroundColor(this.c().settingsField)
              .border({ width: 1, color: this.c().borderL2 })
              .onClick((): void => {
                this.connectHost(host);
              })
            }
          }, (host: DshHost) => {
            return host.id + host.baseUrl;
          })
        }
      }

      if (this.error.length > 0) {
        Column({ space: 6 }) {
          Text(this.error)
            .fontSize(13)
            .fontColor(this.c().danger)
          if (this.failedHostId.length > 0) {
            Text('删除这条失效记录')
              .fontSize(13)
              .fontColor(this.c().link)
              .onClick((): void => {
                let target: DshHost | null = null;
                for (const h of this.hosts) {
                  if (h.id === this.failedHostId) {
                    target = h;
                  }
                }
                if (target !== null) {
                  this.persistHosts(removeHost(this.hosts, target));
                }
                this.error = '';
                this.failedHostId = '';
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Row() {
        Text('导入桥配置（DSH1 文本）')
          .fontSize(14)
          .fontColor(this.c().labelSecondary)
        Blank()
        Text(this.importOpen ? '收起' : '展开')
          .fontSize(13)
          .fontColor(this.c().link)
          .onClick((): void => {
            this.importOpen = !this.importOpen;
          })
      }
      .width('100%')

      if (this.importOpen) {
        TextArea({ placeholder: '粘贴 DSH1 导入文本', text: this.importText })
          .fontSize(14)
          .fontColor(this.c().labelPrimary)
          .placeholderColor(this.c().inputHintText)
          .backgroundColor(this.c().inputFill)
          .borderRadius(12)
          .border({ width: 1, color: this.c().borderL2 })
          .maxLines(3)
          .width('100%')
          .onChange((value: string): void => {
            this.importText = value;
          })
        Button('导入并连接')
          .fontSize(15)
          .fontColor(this.c().onBrand)
          .backgroundColor(this.c().brand)
          .borderRadius(12)
          .width('100%')
          .enabled(!this.busy)
          .onClick((): void => {
            this.importConfig();
          })
      }

      TextInput({ placeholder: '桥地址（如 http://127.0.0.1:3090）', text: this.urlText })
        .fontSize(16)
        .fontColor(this.c().labelPrimary)
        .placeholderColor(this.c().inputHintText)
        .placeholderFont({ size: 16 })
        .backgroundColor(this.c().inputFill)
        .borderRadius(12)
        .border({ width: 1, color: this.c().inputBorder })
        .width('100%')
        .height(48)
        .onChange((value: string): void => {
          this.urlText = value;
        })

      TextInput({ placeholder: '配对码', text: this.pairCode })
        .fontSize(16)
        .fontColor(this.c().labelPrimary)
        .placeholderColor(this.c().inputHintText)
        .placeholderFont({ size: 16 })
        .backgroundColor(this.c().inputFill)
        .borderRadius(12)
        .border({ width: 1, color: this.c().borderL2 })
        .width('100%')
        .height(48)
        .onChange((value: string): void => {
          this.pairCode = value;
        })

      Button(this.busy ? '连接中…' : '配对并连接')
        .fontSize(16)
        .fontColor(this.c().onBrand)
        .backgroundColor(this.c().brand)
        .borderRadius(12)
        .width('100%')
        .height(46)
        .enabled(!this.busy)
        .onClick((): void => {
          this.pairAndConnect();
        })
    }
    .width('100%')
    .padding({
      left: DsSpacing.screenPad, right: DsSpacing.screenPad,
      top: 36, bottom: 24,
    })
    .alignItems(HorizontalAlign.Start)
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .backgroundColor(this.c().bgBase)
  }
}
