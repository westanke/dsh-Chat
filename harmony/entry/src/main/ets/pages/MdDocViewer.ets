/**
 * 全屏 Markdown 文档查看页 —— 对照安卓 md_viewer.dart：
 * resolvePath → readFileBytes → utf8 → DsMarkdownView；标题 + 大小 caption；
 * 失败中心图标 + 重试。入口=交付文件卡点 .md（chat_message_items 口径）。
 */

import { ChatStore } from '../core/ChatStore';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from '../components/md/MdView';

@Component
export struct MdDocViewer {
  store: ChatStore | null = null;
  absolutePath: string = '';
  title: string = '';
  onBack: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @State docText: string = '';
  @State sizeLabel: string = '';
  @State error: string = '';
  @State loaded: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.load();
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
          .width(40)
          .height(DsSpacing.topBarHeight)
          .textAlign(TextAlign.Center)
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
          Text('📄').fontSize(32)
          Text(this.error)
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelSecondary)
          Text('重试')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().brand)
            .onClick(() => {
              this.load();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (!this.loaded) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.c().brand)
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
    .backgroundColor(this.c().bgBase)
  }
}
