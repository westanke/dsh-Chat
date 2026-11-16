/**
 * 会话权限档位 sheet —— 从 Composer.ets 拆出的权限切换面板
 *（对照安卓 composer_bar.dart _PermissionSheet；core 语义在 Permissions.ts）。
 */

import { ChatStore } from '../core/ChatStore';
import { PermissionCatalog, PermissionOption } from '../core/Permissions';
import { JsonMap } from '../core/JsonAccess';
import { DsColors } from '../ui/theme';

@Component
export struct PermissionSheet {
  @StorageProp('dshDark') dark: boolean = false;
  store: ChatStore | null = null;
  /** 错误/提示回调（Composer 显示在输入条上方）。 */
  onDone: (message: string) => void = (m: string): void => {
    void m;
  };
  @State options: PermissionOption[] = [];
  @State current: string = '';

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    if ((st.sessionId ?? '').length === 0) {
      this.onDone('请先打开一个会话再切换权限档位');
      return;
    }
    st.api.permissionOptionsRaw().then((data: JsonMap): void => {
      const catalog: PermissionCatalog = PermissionCatalog.fromJson(data);
      this.options = catalog.switchable;
      this.current = st.currentPermission ?? '';
    }).catch((): void => {
      this.onDone('权限档位加载失败');
    });
  }

  private pick(v: string): void {
    let chosen: PermissionOption | null = null;
    for (const o of this.options) {
      if (o.value === v) {
        chosen = o;
        break;
      }
    }
    if (chosen === null) {
      return;
    }
    if (chosen.needsConfirm) {
      AlertDialog.show({
        title: '切换到完全权限？',
        message: '该档位不受沙箱限制。',
        primaryButton: {
          value: '取消',
          action: (): void => {
          },
        },
        secondaryButton: {
          value: '确认',
          action: (): void => {
            this.apply(v);
          },
        },
      });
      return;
    }
    this.apply(v);
  }

  private apply(v: string): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    let label: string = v;
    for (const o of this.options) {
      if (o.value === v) {
        label = o.label;
        break;
      }
    }
    st.setPermission(v).then((): void => {
      this.current = v;
      this.onDone('权限已切换为「' + label + '」');
    }).catch((): void => {
      this.onDone('权限切换失败');
    });
  }

  build() {
    Column() {
      Text('会话权限档位')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })
      ForEach(this.options, (o: PermissionOption) => {
        Row({ space: 10 }) {
          Text(this.current === o.value ? '✓' : '○')
            .fontSize(16)
            .fontColor(this.current === o.value ? this.c().brand : this.c().labelTertiary)
          Column({ space: 2 }) {
            Text(o.label)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c().labelPrimary)
            if (o.descriptionLabel !== null) {
              Text(o.descriptionLabel)
                .fontSize(12)
                .fontColor(this.c().labelTertiary)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .accessibilityText(o.label + (o.descriptionLabel !== null ? '：' + o.descriptionLabel : ''))
        .onClick(() => {
          this.pick(o.value);
        })
      }, (o: PermissionOption) => o.value)
    }
    .width('100%')
    .backgroundColor(this.c().bgBase)
    .padding({ bottom: 12 })
  }
}
