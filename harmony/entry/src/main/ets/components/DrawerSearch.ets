/**
 * 抽屉搜索（标题本地过滤在 SessionsDrawer，正文命中在这里）。
 *
 * 正文搜索走 dshrb-v1 的 `session/search`：目录里没这个端点时静默降级为
 * 标题过滤（不把「不支持」当失败弹给用户）；300ms 防抖；三种结局分开
 * （搜索中 / 搜不了 / 没搜到），部署侧索引可能 `openAt:"never"`，所以
 * 空结果文案不写死「没有匹配」。
 */

import { ChatStore } from '../core/ChatStore';
import { SessionSearchHit, parseSessionSearchHits } from '../core/SessionSearch';
import { kernelSearchSupportedOn, searchSessionsOn } from '../core/GatewayKernel';
import { DsColors, DsSpacing } from '../ui/theme';

@Component
export struct DrawerSearch {
  store: ChatStore | null = null;
  /** 与父组件共享的搜索词（父层用它做标题过滤）。 */
  @Link query: string;
  /** 父层刷新版本：目录晚到/连接变化时重算能力位。 */
  @Prop @Watch('syncVersion') version: number = 0;
  onOpenId: ((id: string) => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @State bodyHits: SessionSearchHit[] = [];
  @State searching: boolean = false;
  @State searchError: string = '';
  @State searchSupported: boolean = false;
  private searchTimer: number = -1;

  /** 把宿主长错误翻成人话：索引禁用是部署配置，不是「没搜到」。 */
  private reasonOf(raw: string): string {
    if (raw.indexOf('session search is disabled') >= 0 || raw.indexOf('session-query index') >= 0) {
      return '正文搜索未启用（宿主未配置会话索引），只能按标题搜索';
    }
    return raw;
  }

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** 命中行标题：按 sessionId 找本地会话标题，找不到退回 id（桥只回 id+片段）。 */
  private titleOf(hit: SessionSearchHit): string {
    const st: ChatStore | null = this.store;
    if (st !== null) {
      for (let i = 0; i < st.sessions.length; i++) {
        if (st.sessions[i].id === hit.sessionId) {
          return st.sessions[i].displayTitle;
        }
      }
    }
    return hit.sessionId;
  }

  aboutToAppear(): void {
    this.syncVersion();
  }

  aboutToDisappear(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }

  /** version 变 → 能力位重算；目录晚到时把已输入的查询补发一次。 */
  syncVersion(): void {
    const supported: boolean = this.store !== null && kernelSearchSupportedOn(this.store.gateway);
    if (supported === this.searchSupported) {
      return;
    }
    this.searchSupported = supported;
    if (supported && this.query.trim() !== '' && this.bodyHits.length === 0) {
      this.scheduleSearch();
    }
  }

  private setQuery(value: string): void {
    this.query = value;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (value.trim() === '') {
      this.bodyHits = [];
      this.searching = false;
      this.searchError = '';
      return;
    }
    this.scheduleSearch();
  }

  private scheduleSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    const self: DrawerSearch = this;
    this.searchTimer = setTimeout((): void => {
      self.searchTimer = -1;
      self.runSearch();
    }, 300);
  }

  private runSearch(): void {
    const st: ChatStore | null = this.store;
    const q: string = this.query.trim();
    if (st === null || q === '') {
      return;
    }
    if (!this.searchSupported) {
      this.bodyHits = [];
      return;
    }
    this.searching = true;
    this.searchError = '';
    const self: DrawerSearch = this;
    searchSessionsOn(st.gateway, q).then((result): void => {
      self.searching = false;
      if (!result.ok) {
        self.bodyHits = [];
        self.searchError = '搜索不可用：' + self.reasonOf(result.message());
        return;
      }
      self.bodyHits = parseSessionSearchHits(result.value, 20);
    }).catch((err: Error): void => {
      self.searching = false;
      self.bodyHits = [];
      self.searchError = '搜索不可用：' + self.reasonOf(err.message);
    });
  }

  build() {
    Column() {
      TextInput({ placeholder: '搜索对话内容...', text: this.query })
        .height(DsSpacing.drawerSearchHeight)
        .fontSize(14)
        .fontColor(this.c().labelPrimary)
        .placeholderColor(this.c().labelTertiary)
        .backgroundColor(this.c().inputFill)
        .borderRadius(20)
        .padding({ left: 14, right: 14 })
        .margin({ left: 12, right: 12, top: 10, bottom: 8 })
        .onChange((value: string): void => {
          this.setQuery(value);
        })
      if (this.query.trim() !== '') {
        if (this.searching) {
          Text('搜索中…')
            .fontSize(12)
            .fontColor(this.c().labelTertiary)
            .padding({ left: 16, top: 4, bottom: 4 })
        } else if (this.searchError !== '') {
          Text(this.searchError)
            .fontSize(12)
            .fontColor(this.c().labelTertiary)
            .maxLines(2)
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        } else if (this.bodyHits.length > 0) {
          Text('正文命中 ' + this.bodyHits.length.toString())
            .fontSize(10)
            .fontColor(this.c().drawerGroupLabel)
            .padding({ left: 16, top: 6, bottom: 2 })
          Column() {
            Repeat<SessionSearchHit>(this.bodyHits)
              .each((entry: RepeatItem<SessionSearchHit>) => {
                this.bodyHitRow(entry.item)
              })
              .key((entry: SessionSearchHit) => entry.sessionId + entry.snippet.length.toString())
          }
          .width('100%')
        } else if (this.searchSupported) {
          Text('没有搜到正文内容（标题匹配见下方）')
            .fontSize(12)
            .fontColor(this.c().labelTertiary)
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        }
      }
    }
    .width('100%')
  }

  @Builder
  bodyHitRow(hit: SessionSearchHit) {
    Column({ space: 2 }) {
      Text(this.titleOf(hit))
        .fontSize(14)
        .fontColor(this.c().labelPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(hit.snippet)
        .fontSize(12)
        .fontColor(this.c().labelSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .visibility(hit.snippet === '' ? Visibility.None : Visibility.Visible)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .onClick((): void => {
      if (this.onOpenId !== null) {
        this.onOpenId(hit.sessionId);
      }
    })
  }
}
