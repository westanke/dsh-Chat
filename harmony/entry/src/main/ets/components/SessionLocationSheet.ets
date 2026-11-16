/**
 * 新建会话工作目录选择 —— 对照安卓 app/lib/ui/session_location_sheet.dart。
 * 用户反馈（2026-11-16）：「安卓新建会话有默认目录，可选目录」。
 *
 * 入口：空态问候区下方的「工作目录：…」chip（仅未发首条消息时可见）。
 * 默认项 = 手机会话（不选目录，走 workspaceId 通道）；也可选最近用过的
 * 目录或从授权根逐级浏览。选中后写 store.pendingLocation，首条消息
 * 走 session-create{rootId,cwd}。
 */

import { ChatStore } from '../core/ChatStore';
import { GatewayEntry, GatewayRoot } from '../core/Files';
import {
  SessionLocation, locationLabel, locationSubtitle, parentPath, recentLocations,
} from '../core/SessionLocation';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct SessionLocationSheet {
  store: ChatStore | null = null;
  /** 关闭面板（选完/点遮罩都要回）。 */
  onClose: () => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  /** 当前选择（父层传下来的快照）。 */
  @Prop current: SessionLocation | null = null;
  @State recentsView: SessionLocation[] = [];
  /** 浏览态：null=主列表；非 null=浏览中（path 为根内相对路径）。 */
  @State browsing: boolean = false;
  @State browseRootId: string = '';
  @State browseRootLabel: string = '';
  @State browsePath: string = '';
  @State entriesView: GatewayEntry[] = [];
  @State loading: boolean = false;
  @State failed: boolean = false;
  @State rootsLoaded: boolean = false;
  /** 授权根（浏览时可在多根间切换；首个根常是空的 default-workspace）。 */
  @State rootsView: GatewayRoot[] = [];
  /** 当前浏览的根下标。 */
  @State rootIdx: number = 0;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.syncRecents();
    this.loadRootsIfNeeded();
  }

  private syncRecents(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    this.recentsView = recentLocations(st.sessions);
  }

  private loadRootsIfNeeded(): void {
    const st: ChatStore | null = this.store;
    if (st === null || this.rootsLoaded) {
      return;
    }
    st.api.listRootsRest().then((roots: GatewayRoot[]): void => {
      this.rootsLoaded = true;
      this.rootsView = roots;
      if (roots.length > 0) {
        this.rootIdx = 0;
        this.browseRootId = roots[0].id;
        this.browseRootLabel = roots[0].label;
      }
    }).catch((): void => {
      this.rootsLoaded = true;
    });
  }

  /**
   * 逐级浏览（''=根）。根目录为空时自动换到下一个有子目录的根 ——
   * 实测首个授权根常是空的 `default-workspace`（安卓走 file-list 的
   * 「首个授权根」语义，REST 必须显式给 rootId，故这里跳空根）。
   */
  private browse(path: string): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    this.browsePath = path;
    this.loading = true;
    this.failed = false;
    this.browseFrom(this.rootIdx, path);
  }

  private browseFrom(idx: number, path: string): void {
    const st: ChatStore | null = this.store;
    if (st === null || idx >= this.rootsView.length) {
      this.loading = false;
      this.failed = true;
      return;
    }
    const root: GatewayRoot = this.rootsView[idx];
    st.api.listEntriesRest(root.id, path)
      .then((entries: GatewayEntry[]): void => {
        const dirs: GatewayEntry[] = [];
        for (const e of entries) {
          if (e.isDirectory) {
            dirs.push(e);
          }
        }
        // 根目录无子目录 → 换下一个根（仅根层自动跳，下钻不跳）。
        if (dirs.length === 0 && path === '' && idx + 1 < this.rootsView.length) {
          this.browseFrom(idx + 1, path);
          return;
        }
        this.rootIdx = idx;
        this.browseRootId = root.id;
        this.browseRootLabel = root.label;
        this.entriesView = dirs;
        this.loading = false;
      }).catch((): void => {
        if (path === '' && idx + 1 < this.rootsView.length) {
          this.browseFrom(idx + 1, path);
          return;
        }
        this.loading = false;
        this.failed = true;
      });
  }

  /** 手动切到下一个授权根（多根时头部显示「根 N/M」）。 */
  private switchRoot(): void {
    if (this.rootsView.length <= 1) {
      return;
    }
    const next: number = (this.rootIdx + 1) % this.rootsView.length;
    this.rootIdx = next;
    this.browseFrom(next, '');
  }

  private pick(loc: SessionLocation): void {
    const st: ChatStore | null = this.store;
    if (st !== null) {
      st.pendingLocation = loc;
    }
    this.onClose();
  }

  private pickDefault(): void {
    const st: ChatStore | null = this.store;
    if (st !== null) {
      st.pendingLocation = null;
    }
    this.onClose();
  }

  /** 主列表项（默认 / 最近 / 浏览入口）。 */
  @Builder
  choiceRow(icon: string, title: string, subtitle: string, picked: boolean,
    onTap: () => void) {
    Row({ space: 10 }) {
      Text(icon)
        .fontSize(16)
      Column({ space: 2 }) {
        Text(title)
          .fontSize(DsTypography.base.size)
          .fontColor(this.c().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(DsTypography.small.size)
            .fontColor(picked ? this.c().brand : this.c().labelTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (picked) {
        Text('✓')
          .fontSize(16)
          .fontColor(this.c().brand)
      }
    }
    .width('100%')
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, top: 12, bottom: 12 })
    .accessibilityText('选择此目录')
    .onClick(onTap)
  }

  build() {
    Column() {
      if (this.browsing) {
        this.browseHeader()
      } else {
        Text('会话工作目录')
          .fontSize(DsTypography.h4.size)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.c().labelPrimary)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, top: 16, bottom: 4 })
        Text('新建会话默认落到「手机会话」工作区；也可以指定授权根下的某个目录。目录在会话创建时定死，历史会话不受影响。')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelSecondary)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 12 })
      }
      Scroll() {
        Column() {
          if (this.browsing) {
            this.browseList()
          } else {
            this.mainList()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  mainList() {
    this.choiceRow('📱', '手机会话（默认）',
      this.current === null ? '当前选择' : '点此恢复默认',
      this.current === null, (): void => {
        this.pickDefault();
      })
    if (this.current !== null) {
      this.choiceRow('📁', this.current.label, '当前选择', true, (): void => {
        this.onClose();
      })
    }
    if (this.recentsView.length > 0) {
      Text('最近使用')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
        .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, top: 8, bottom: 4 })
      ForEach(this.recentsView, (item: SessionLocation) => {
        if (this.current === null || this.current.key !== item.key) {
          this.choiceRow('📁', item.label, this.subtitleOf(item), false, (): void => {
            this.pick(item);
          })
        }
      }, (item: SessionLocation) => item.key)
    }
    this.choiceRow('📂', '浏览授权根目录…', '', false, (): void => {
      this.browsing = true;
      this.browse('');
    })
  }

  private subtitleOf(item: SessionLocation): string {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return '';
    }
    return locationSubtitle(st.sessions, item);
  }

  @Builder
  browseHeader() {
    Row({ space: 8 }) {
      Text('‹')
        .fontSize(20)
        .fontColor(this.c().brand)
        .width(36)
        .textAlign(TextAlign.Center)
        .accessibilityText('返回上级目录')
        .onClick((): void => {
          if (this.browsePath === '') {
            this.browsing = false;
            this.entriesView = [];
          } else {
            this.browse(parentPath(this.browsePath));
          }
        })
      Column({ space: 2 }) {
        Text('选择工作目录')
          .fontSize(DsTypography.h4.size)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.c().labelPrimary)
        Text(this.browseRootLabel === ''
          ? (this.browsePath === '' ? '根目录' : this.browsePath)
          : this.browseRootLabel + (this.browsePath === '' ? '' : '/' + this.browsePath))
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .accessibilityText(this.browseRootLabel === '' ? '选择根目录' : '切换根目录：' + this.browseRootLabel)
      .onClick((): void => {
        this.switchRoot();
      })
      Text('用此目录')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().brand)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .accessibilityText('用此目录')
        .onClick((): void => {
          this.pick(new SessionLocation(this.browseRootId, this.browsePath,
            locationLabel(this.browsePath)));
        })
    }
    .width('100%')
    .padding({ left: 4, right: DsSpacing.screenPad, top: 12, bottom: 8 })
  }

  @Builder
  browseList() {
    if (this.loading) {
      Text('读取目录…')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
        .padding(16)
    } else if (this.failed) {
      Text('读取目录失败，点按重试')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().danger)
        .width('100%')
        .padding(16)
        .accessibilityText('读取目录失败，点按重试')
        .onClick((): void => {
          this.browse(this.browsePath);
        })
    } else if (this.entriesView.length === 0) {
      Text('此目录下没有子目录')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
        .padding(16)
    } else {
      ForEach(this.entriesView, (e: GatewayEntry) => {
        Row({ space: 10 }) {
          Text('📁')
            .fontSize(16)
          Text(e.name)
            .fontSize(DsTypography.base.size)
            .fontColor(this.c().labelPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('›')
            .fontSize(16)
            .fontColor(this.c().labelTertiary)
        }
        .width('100%')
        .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, top: 12, bottom: 12 })
        .accessibilityText('进入 ' + e.name)
        .onClick((): void => {
          this.browse(e.path);
        })
      }, (e: GatewayEntry) => e.path)
    }
  }
}
