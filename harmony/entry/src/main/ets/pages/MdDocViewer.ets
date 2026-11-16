/**
 * 全屏 Markdown 文档查看页 —— 对照安卓 md_viewer.dart：
 * resolvePath → readFileBytes → utf8 → DsMarkdownView；标题 + 大小 caption；
 * 失败中心图标 + 重试。入口=交付文件卡点 .md（chat_message_items 口径）。
 */

import { window, mediaquery } from '@kit.ArkUI';
import { ChatStore } from '../core/ChatStore';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from '../components/md/MdView';
import { BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd } from '../core/Breakpoints';

@Component
export struct MdDocViewer {
  store: ChatStore | null = null;
  absolutePath: string = '';
  title: string = '';
  onBack: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** 窗口宽度断点（R007 一多）：标题行与返回键按档放大。 */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;
  @State docText: string = '';
  @State sizeLabel: string = '';
  @State error: string = '';
  @State loaded: boolean = false;
  /** 状态栏高度（vp）：bindContentCover 全屏模态不自动避让状态栏，须自己让。 */
  @State topInset: number = 0;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** 窗口断点自读（R007 一多）：标题行与返回键在宽屏加高。 */
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
      // 拿不到 mediaquery 时按手机档渲染，不阻塞文档打开。
    }
  }

  private atLeastMd(): boolean {
    return atLeastMd(this.bp);
  }

  aboutToAppear(): void {
    this.refreshBreakpoint();
    this.load();
    // 全屏模态（bindContentCover）内容从屏幕顶起，不含系统安全区；取状态栏高度补顶部内边距，
    // 否则标题与返回键被状态栏盖住（真机实证）。
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      const avoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(avoid.topRect.height);
    }).catch((): void => {
      // 拿不到就退回 0，不影响正文渲染。
    });
  }

  load(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      this.error = '连接不可用';
      return;
    }
    this.error = '';
    st.api.resolvePathRest(this.absolutePath).then((f): Promise<string> => {
      return st.api.readFileBytes(f.rootId, f.path);
    }).then((text: string): void => {
      this.docText = text;
      const kb: number = Math.max(1, Math.round(text.length / 1024));
      this.sizeLabel = kb >= 1024
        ? ((kb / 1024).toFixed(1) + ' MB')
        : (kb + ' KB');
      this.loaded = true;
    }).catch((e: Error): void => {
      this.error = e.message;
      this.loaded = false;
    });
  }

  build() {
    Column() {
      // 顶栏
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
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(DsTypography.pageTitle.size)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c().labelPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.sizeLabel.length > 0) {
            Text(this.sizeLabel)
              .fontSize(DsTypography.caption.size)
              .fontColor(this.c().labelTertiary)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(DsSpacing.topBarHeight)
      .padding({ left: DsSpacing.screenPad - 14, right: DsSpacing.screenPad - 14 })
      Divider().color(this.c().borderL1).strokeWidth(1)

      if (this.error.length > 0) {
        Column({ space: 12 }) {
          Text('📄').fontSize(30)
          Text(this.error)
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelSecondary)
          Text('重试')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().brand)
            .accessibilityText('重试')
            .onClick(() => {
              this.load();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (!this.loaded) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.c().brand)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            MdView({ text: this.docText, streaming: false })
          }
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
            top: DsSpacing.blockGap, bottom: DsSpacing.blockGap * 2 })
        }
        .align(Alignment.Top)
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset })
    .backgroundColor(this.c().bgBase)
  }
}
