/**
 * 子会话（团队成员）历史查看页 —— 对齐安卓 app/lib/ui/subagent_history_page.dart。
 *
 * REST 只读窄口 GET /chat/sessions/{leadId}/subagents/{subagentId}/messages：
 * Lead 可见 + 内核投影背书成员关系，只读不可写（无输入条）。
 * 轻量渲染：正文 / 过程短语 / 错误 / 文件卡，不复用 MessageActions 等交互回路。
 */

import { mediaquery, window } from '@kit.ArkUI';

import { ChatStore } from '../core/ChatStore';
import { ChatMessage, DeliverableFile, HistoryPage } from '../core/HistoryPage';
import { SubagentRow } from '../core/Projections';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from '../components/md/MdView';
import { BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd } from '../core/Breakpoints';

@Component
export struct SubagentHistoryPage {
  store: ChatStore | null = null;
  leadSessionId: string = '';
  subagent: SubagentRow = new SubagentRow();
  onBack: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @State msgs: ChatMessage[] = [];
  @State hasMore: boolean = false;
  @State loading: boolean = true;
  @State loadingOlder: boolean = false;
  @State error: string = '';
  /** bindContentCover 全屏模态不避让状态栏，自己补（MdDocViewer 同款）。 */
  @State topInset: number = 0;
  @StorageProp('dshBreakpoint') bp: string = BP_SM;

  /** 窗口断点自读（R007 一多）：返回钮在宽屏放大一档。 */
  private refreshBreakpoint(): void {
    try {
      const md: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_MD);
      const lg: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_LG);
      this.bp = breakpointOf(md.matches, lg.matches);
    } catch (e) {
      // 拿不到 mediaquery 时按手机档渲染。
    }
  }

  private backSize(): number {
    return atLeastMd(this.bp) ? 48 : 44;
  }

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.refreshBreakpoint();
    this.load();
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window): void => {
        const avoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.topInset = px2vp(avoid.topRect.height);
      }).catch((): void => {
        // 拿不到就退回 0。
      });
    } catch (e) {
      // 非 UI 上下文（单测/预览）忽略。
    }
  }

  private api(): ChatStore | null {
    return this.store;
  }

  private title(): string {
    if (this.subagent.label.length > 0) {
      return this.subagent.label;
    }
    const id: string = this.subagent.id;
    return '子会话 ' + (id.length > 8 ? id.substring(0, 8) : id);
  }

  load(): void {
    const st: ChatStore | null = this.api();
    if (st === null) {
      this.error = '连接不可用';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.error = '';
    st.api.subagentHistory(this.leadSessionId, this.subagent.id, 80, 0)
      .then((page: HistoryPage): void => {
        this.msgs = page.items;
        this.hasMore = page.hasMore;
        this.loading = false;
      })
      .catch((e: Error): void => {
        this.error = e.message;
        this.loading = false;
      });
  }

  /** 翻页：以当前最旧一条 seq>=0 的事件为 beforeSeq 续拉，前插。 */
  private loadOlder(): void {
    const st: ChatStore | null = this.api();
    if (st === null || this.loadingOlder) {
      return;
    }
    let oldest: number = -1;
    for (const m of this.msgs) {
      if (m.seq >= 0 && (oldest < 0 || m.seq < oldest)) {
        oldest = m.seq;
      }
    }
    if (oldest < 0) {
      return;
    }
    this.loadingOlder = true;
    st.api.subagentHistory(this.leadSessionId, this.subagent.id, 80, oldest)
      .then((page: HistoryPage): void => {
        const merged: ChatMessage[] = [];
        for (const m of page.items) {
          merged.push(m);
        }
        for (const m of this.msgs) {
          merged.push(m);
        }
        this.msgs = merged;
        this.hasMore = page.hasMore;
        this.loadingOlder = false;
      })
      .catch((): void => {
        this.loadingOlder = false;
      });
  }

  build() {
    Column() {
      // 顶栏：返回 / 标题 / 占位（保持标题居中）
      Row({ space: 8 }) {
        Text('‹')
          .fontSize(DsTypography.h3.size)
          .fontColor(this.c().labelPrimary)
          .width(this.backSize())
          .height(this.backSize())
          .textAlign(TextAlign.Center)
          .accessibilityText('返回')
          .onClick((): void => {
            const cb = this.onBack;
            if (cb !== null) {
              cb();
            }
          })
        Text(this.title())
          .fontSize(DsTypography.pageTitle.size)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Blank().width(40)
      }
      .width('100%')
      .height(44)
      .padding({ left: 4, right: 4 })
      .margin({ top: this.topInset })

      if (this.loading) {
        Row() {
          LoadingProgress().width(40).height(40).color(this.c().brand)
            .accessibilityText('正在加载')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.error.length > 0) {
        Column({ space: 12 }) {
          Text(this.error)
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().danger)
            .textAlign(TextAlign.Center)
          Text('重试')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().brand)
            .height(40)
            .padding({ left: 16, right: 16 })
            .accessibilityText('重试')
            .onClick((): void => {
              this.load();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(DsSpacing.screenPad)
      } else {
        List({ space: 0 }) {
          if (this.hasMore) {
            ListItem() {
              Row({ space: 6 }) {
                if (this.loadingOlder) {
                  LoadingProgress().width(18).height(18).color(this.c().brand)
                } else {
                  Text('加载更早消息')
                    .fontSize(DsTypography.small.size)
                    .fontColor(this.c().brand)
                }
              }
              .width('100%')
              .height(40)
              .justifyContent(FlexAlign.Center)
              .accessibilityText('加载更早消息')
              .onClick((): void => {
                this.loadOlder();
              })
            }
          }
          Repeat<ChatMessage>(this.msgs)
            .each((entry: RepeatItem<ChatMessage>) => {
              ListItem() {
                this.row(entry.item)
              }
            })
            .key((entry: ChatMessage) => entry.role + '-' + entry.seq.toString()
              + '-' + entry.text.length.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, top: 8, bottom: 22 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c().bgBase)
  }

  /** 单条只读消息：过程短语 / 错误 / 文件卡 / 用户气泡 / assistant 正文。 */
  @Builder
  row(m: ChatMessage) {
    Column() {
      if (m.isProcess) {
        Text(m.phraseText)
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelTertiary)
          .width('100%')
      } else if (m.isError) {
        Text(m.text)
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().danger)
          .width('100%')
      } else if (m.role === 'files') {
        Column({ space: DsSpacing.liGap }) {
          Repeat<DeliverableFile>(m.files)
            .each((entry: RepeatItem<DeliverableFile>) => {
              Row({ space: 8 }) {
                Text('📄')
                  .fontSize(14)
                  .fontColor(this.c().brand)
                Text(entry.item.path)
                  .fontSize(DsTypography.small.size)
                  .fontColor(this.c().labelSecondary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
            })
            .key((entry: DeliverableFile) => entry.path)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else if (m.isUser) {
        Row() {
          Text(m.text)
            .fontSize(DsTypography.base.size)
            .fontColor(this.c().userBubbleText)
            .lineHeight(DsTypography.base.lineHeight)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor(this.c().userBubble)
            .borderRadius(DsSpacing.bubbleRadius)
            .constraintSize({ maxWidth: '86.4%' })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      } else {
        MdView({ text: m.text })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: DsSpacing.blockGap })
  }
}
