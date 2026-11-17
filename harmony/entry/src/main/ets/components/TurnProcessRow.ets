/// 轮尾行（官方 TurnProcessNodeView）：「已完成，用时 N」/「处理失败」。样式：
/// 高 33、底部 0.5px 分隔线、labelTertiary（hover→secondary 无 hover 口径，降级
/// 常色）、正文级字号、padding 0 0 8px、标题在左 chevron 紧随右（14px；官方
/// rotate 180° 用 ⌃/⌄ 字符降级）、整行可点（!canCollapse 不响应）。数字段
/// tabular-nums 降级为 monospace 字族。轮尾信息由本组件现算（core/TurnTail.
/// turnTailOf，node 直测）：仅闭合轮渲染；点开 = 整轮过程组 setExpanded。
import { ChatMessage } from '../core/HistoryPage';
import { TurnTailInfo, turnTailOf, turnTailLabel, durationPartsOf, DurationPart } from '../core/TurnTail';
import { ChatStore } from '../core/ChatStore';
import { DsColors, DsTypography } from '../ui/theme';

@Component
export struct TurnProcessRow {
  /** 所属 store（消息数组/流式态/展开集合）。 */
  store: ChatStore | null = null;
  /** 轮内最后一条 assistant 消息（轮尾信息以它为锚现算）。 */
  msg: ChatMessage = new ChatMessage();
  /** 父列表版本（changed/reload 后 bump）→ 重渲染并重算轮尾。 */
  @Prop version: number = 0;
  @StorageProp('dshDark') dark: boolean = false;
  @State open: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private info(): TurnTailInfo | null {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return null;
    }
    let idx: number = -1;
    for (let i = 0; i < st.messages.length; i++) {
      if (st.messages[i] === this.msg) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return null;
    }
    return turnTailOf(st.messages, idx, st.streaming);
  }

  /** 可点 = 有可展开内容（foldable && hasContent && !alwaysOpen 口径）。 */
  private canCollapse(): boolean {
    const info: TurnTailInfo | null = this.info();
    return info !== null && info.hasContent;
  }

  private toggle(): void {
    if (!this.canCollapse()) {
      return;
    }
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    const info: TurnTailInfo = this.info() as TurnTailInfo;
    this.open = !this.open;
    st.workSteps.setExpanded(info.groupKeys, this.open);
    st.changed();
  }

  private parts(): DurationPart[] {
    const info: TurnTailInfo | null = this.info();
    return info === null || info.durationMs === null ? [] : durationPartsOf(info.durationMs as number);
  }

  private label(): string {
    const info: TurnTailInfo | null = this.info();
    if (info === null) {
      return '';
    }
    return turnTailLabel(info, info.durationMs === null ? null : this.parts());
  }

  build() {
    if (this.info() !== null) {
      Row({ space: 0 }) {
        Text(this.label())
          .fontSize(DsTypography.small.size)
          .fontColor(this.labelColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        if (this.showParts()) {
          ForEach(this.parts(), (p: DurationPart) => {
            if (p.numeric) {
              Text(p.text)
                .fontSize(DsTypography.small.size)
                .fontFamily('monospace')
                .fontColor(this.labelColor())
                .flexShrink(0)
            } else {
              Text(p.text)
                .fontSize(DsTypography.small.size)
                .fontColor(this.labelColor())
                .flexShrink(0)
            }
          }, (p: DurationPart, idx: number) => idx.toString() + '-' + p.text)
        }
        if (this.canCollapse()) {
          Text(this.open ? '⌃' : '⌄')
            .fontSize(14)
            .fontColor(this.labelColor())
            .width(14)
            .textAlign(TextAlign.Center)
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .height(33)
      .padding({ top: 2, bottom: 8 })
      .borderWidth({ bottom: 0.5 })
      .borderColor(this.c().inputBorder)
      .accessibilityText(this.label() + (this.canCollapse() ? (this.open ? '，收起' : '，展开') : ''))
      .onClick((): void => {
        this.toggle();
      })
    }
  }

  private showParts(): boolean {
    const info: TurnTailInfo | null = this.info();
    return info !== null && info.durationMs !== null;
  }

  private labelColor(): string {
    const info: TurnTailInfo | null = this.info();
    if (info !== null && info.failed) {
      return this.c().danger;
    }
    return this.c().labelTertiary;
  }
}
