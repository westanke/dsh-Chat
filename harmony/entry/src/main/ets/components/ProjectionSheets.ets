/**
 * 投影面板四件 + 统计 —— 对照安卓 projection_sheets.dart/stats_sheet.dart：
 * 运行轨迹（本地 rawEvents 分组，点节点展开原始 JSON）/ 智能团队（成员/任务/
 * 子会话 + 三枚指挥话术）/ 任务 / 会话统计。全部本地只读，不发请求。
 * 各面板由 ChatView 挂 bindSheet。骨架（title+subtitle+内容区）每件内联
 * （ArkTS @BuilderParam 传 lambda 不可靠，不用）。
 * 智能团队 / 任务已切到 ProjectionTeamSheets.ets（单文件 ≤500 行）。
 */

import { ChatStore } from '../core/ChatStore';
import { TrajectoryTurn, TrajectoryNode, TrajectoryNodeKind, trajectoryOf,
  prettyJson, chatStatsOf } from '../core/Projections';
import { ChatMessage } from '../core/HistoryPage';
import { GatewayState } from '../core/GatewayEvents';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct StatsSheet {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** 键序稳定（Map.forEach 顺序即插入序）。 */
  @State keys: string[] = ['消息总数', '用户消息', '助手回复', '工具过程组', '错误提示', '工具调用', '思考块'];

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private countOf(k: string): number {
    const st: ChatStore | null = this.store;
    const msgs: ChatMessage[] = st === null ? [] : st.messages;
    return chatStatsOf(msgs).get(k) ?? 0;
  }

  build() {
    Column() {
      Text('会话统计')
        .fontSize(DsTypography.h4.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .width('100%')
      Text('由当前会话已加载的消息本地计算，不产生网络请求。')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelSecondary)
        .width('100%')
        .margin({ top: DsSpacing.liGap })
      Repeat<string>(this.keys)
        .each((item: RepeatItem<string>) => {
          Row() {
            Text(item.item)
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().labelSecondary)
              .layoutWeight(1)
            Text(this.countOf(item.item).toString())
              .fontSize(DsTypography.smallStrong.size)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c().labelPrimary)
          }
          .width('100%')
          .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
        })
        .key((item: string) => item)
    }
    .width('100%')
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
      top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    .backgroundColor(this.c().bgLayer1)
  }
}

/** 轨迹/团队/任务共用的骨架行为（title+subtitle+滚动内容）。
 *  showHeader=false 供代码工作视图第一段内联复用（隐藏标题/说明，只留轨迹流）。 */
@Component
export struct TrajectorySheet {
  store: ChatStore | null = null;
  @Prop showHeader: boolean = true;
  @StorageProp('dshDark') dark: boolean = false;
  @State expandedSeq: number = -1;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private turns(): TrajectoryTurn[] {
    const st: ChatStore | null = this.store;
    return st === null ? [] : trajectoryOf(st.rawEvents);
  }

  private nodeLabel(n: TrajectoryNode): string {
    if (n.kind === TrajectoryNodeKind.USER) {
      return '用户消息';
    }
    if (n.kind === TrajectoryNodeKind.ASSISTANT) {
      return '助手回复';
    }
    if (n.kind === TrajectoryNodeKind.TOOL) {
      return n.label.length === 0 ? '工具调用' : '工具调用 · ' + n.label;
    }
    if (n.kind === TrajectoryNodeKind.DELIVERABLE) {
      return '交付物';
    }
    if (n.kind === TrajectoryNodeKind.TURN_END) {
      return '回合结束';
    }
    return n.type;
  }

  private nodeIcon(n: TrajectoryNode): string {
    if (n.kind === TrajectoryNodeKind.USER) {
      return '👤';
    }
    if (n.kind === TrajectoryNodeKind.ASSISTANT) {
      return '🤖';
    }
    if (n.kind === TrajectoryNodeKind.TOOL) {
      return '🔧';
    }
    if (n.kind === TrajectoryNodeKind.DELIVERABLE) {
      return '📎';
    }
    if (n.kind === TrajectoryNodeKind.TURN_END) {
      return '🏁';
    }
    return '⋯';
  }

  build() {
    Column() {
      if (this.showHeader) {
        Text('运行轨迹')
          .fontSize(DsTypography.h4.size)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c().labelPrimary)
          .width('100%')
        Text('由当前会话的原始历史事件本地分组，不产生网络请求；点节点展开原始 JSON。')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelSecondary)
          .width('100%')
          .margin({ top: DsSpacing.liGap })
      }
      Scroll() {
        Column() {
          if (this.turns().length === 0) {
            Text('这个会话还没有可回溯的历史。')
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().labelSecondary)
              .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
              .width('100%')
          }
          Repeat<TrajectoryTurn>(this.turns())
            .each((entry: RepeatItem<TrajectoryTurn>) => {
              this.turnBlock(entry.item)
            })
            .key((entry: TrajectoryTurn) => 'turn' + entry.turn.toString() + '-' + entry.nodes.length.toString())
        }
        .width('100%')
      }
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)
      .margin({ top: DsSpacing.blockGap })
    }
    .width('100%')
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
      top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    .backgroundColor(this.c().bgLayer1)
  }

  /** 单个轮次（标题行 + 节点列表）。抽 @Builder 降嵌套深度（R014）并把
   * 内层 if 链从帧里移走，避免静态审计误判 LazyForEach/Repeat 形态。 */
  @Builder
  turnBlock(t: TrajectoryTurn) {
    Column() {
              Row({ space: DsSpacing.chipIconGap }) {
                Text('📈').fontSize(14)
                Text(t.isUnknown ? '轮次之间' : '轮次 ' + t.turn.toString())
                  .fontSize(DsTypography.smallStrong.size)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c().labelPrimary)
                if (t.toolCalls > 0) {
                  Text(t.toolCalls.toString() + ' 个工具调用')
                    .fontSize(DsTypography.caption.size)
                    .fontColor(this.c().labelSecondary)
                }
                Blank()
                if (t.durationMillis !== null) {
                  Text((t.durationMillis as number).toString() + ' ms')
                    .fontSize(DsTypography.caption.size)
                    .fontColor(this.c().labelTertiary)
                }
              }
              .width('100%')
              .padding({ top: DsSpacing.blockGap })
              Repeat<TrajectoryNode>(t.nodes)
                .each((entry: RepeatItem<TrajectoryNode>) => {
                Column() {
                  Row({ space: DsSpacing.liGap }) {
                    Text(this.nodeIcon(entry.item))
                      .fontSize(12)
                    Text(this.nodeLabel(entry.item))
                      .fontSize(DsTypography.small.size)
                      .fontColor(this.c().labelPrimary)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('#' + entry.item.seq.toString())
                      .fontSize(DsTypography.caption.size)
                      .fontColor(this.c().labelTertiary)
                    Text(this.expandedSeq === entry.item.seq ? '⌃' : '⌄')
                      .fontSize(12)
                      .fontColor(this.c().labelSecondary)
                  }
                  .width('100%')
                  .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
                  .accessibilityText('第 ' + entry.item.seq.toString() + ' 条' + (this.expandedSeq === entry.item.seq ? '，收起' : '，展开'))
                  .onClick(() => {
                    this.expandedSeq = this.expandedSeq === entry.item.seq ? -1 : entry.item.seq;
                  })
                  if (this.expandedSeq === entry.item.seq && entry.item.raw !== null) {
                    Text(prettyJson(entry.item.raw))
                      .fontSize(DsTypography.codeBlock.size)
                      .fontColor(this.c().mdCodeBlockText)
                      .padding(DsSpacing.codeBlockPad)
                      .borderRadius(DsSpacing.codeBlockRadius)
                      .backgroundColor(this.c().mdCodeBlockBg)
                      .width('100%')
                  }
                }
                .width('100%')
                .padding({ left: DsSpacing.thinkHMargin })
                })
                .key((entry: TrajectoryNode) => entry.seq.toString() + '-' + entry.type)
    }
    .width('100%')
  }

}

