/**
 * 投影面板四件 + 统计 —— 对照安卓 projection_sheets.dart/stats_sheet.dart：
 * 运行轨迹（本地 rawEvents 分组，点节点展开原始 JSON）/ 智能团队（成员/任务/
 * 子会话 + 三枚指挥话术）/ 待办任务 / 会话统计。全部本地只读，不发请求。
 * 各面板由 ChatView 挂 bindSheet。骨架（title+subtitle+内容区）每件内联
 * （ArkTS @BuilderParam 传 lambda 不可靠，不用）。
 */

import { ChatStore } from '../core/ChatStore';
import { TrajectoryTurn, TrajectoryNode, TrajectoryNodeKind, trajectoryOf, TodoItem,
  todoItems, AgentTeamProjection, agentTeamProjectionOf, prettyJson, chatStatsOf,
  TeamMemberRow, TeamTaskRow, SubagentRow } from '../core/Projections';
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
      ForEach(this.keys, (k: string) => {
        Row() {
          Text(k)
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelSecondary)
            .layoutWeight(1)
          Text(this.countOf(k).toString())
            .fontSize(DsTypography.smallStrong.size)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c().labelPrimary)
        }
        .width('100%')
        .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
      }, (k: string) => k)
    }
    .width('100%')
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
      top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    .backgroundColor(this.c().bgLayer1)
  }
}

/** 轨迹/团队/待办共用的骨架行为（title+subtitle+滚动内容）。 */
@Component
export struct TrajectorySheet {
  store: ChatStore | null = null;
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
      Scroll() {
        Column() {
          if (this.turns().length === 0) {
            Text('这个会话还没有可回溯的历史。')
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().labelSecondary)
              .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
              .width('100%')
          }
          ForEach(this.turns(), (t: TrajectoryTurn) => {
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
              ForEach(t.nodes, (n: TrajectoryNode) => {
                Column() {
                  Row({ space: DsSpacing.liGap }) {
                    Text(this.nodeIcon(n))
                      .fontSize(12)
                    Text(this.nodeLabel(n))
                      .fontSize(DsTypography.small.size)
                      .fontColor(this.c().labelPrimary)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('#' + n.seq.toString())
                      .fontSize(DsTypography.caption.size)
                      .fontColor(this.c().labelTertiary)
                    Text(this.expandedSeq === n.seq ? '⌃' : '⌄')
                      .fontSize(13)
                      .fontColor(this.c().labelSecondary)
                  }
                  .width('100%')
                  .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
                  .onClick(() => {
                    this.expandedSeq = this.expandedSeq === n.seq ? -1 : n.seq;
                  })
                  if (this.expandedSeq === n.seq && n.raw !== null) {
                    Text(prettyJson(n.raw))
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
              }, (n: TrajectoryNode) => n.seq.toString() + '-' + n.type)
            }
            .width('100%')
          }, (t: TrajectoryTurn) => 'turn' + t.turn.toString() + '-' + t.nodes.length.toString())
        }
        .width('100%')
      }
      .align(Alignment.Top)
      .width('100%')
      .margin({ top: DsSpacing.blockGap })
    }
    .width('100%')
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
      top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    .backgroundColor(this.c().bgLayer1)
  }
}

@Component
export struct TeamSheet {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private team(): AgentTeamProjection | null {
    const st: ChatStore | null = this.store;
    return st === null ? null : agentTeamProjectionOf(st.projections);
  }

  private connected(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.connectionState === GatewayState.READY;
  }

  private send(text: string): void {
    const st: ChatStore | null = this.store;
    if (st !== null && this.connected()) {
      st.send(text);
    }
  }

  private memberLeft(m: TeamMemberRow): string {
    return m.name + (m.isLead ? ' · 负责人' : '');
  }

  private memberRight(m: TeamMemberRow): string {
    let s: string = m.role + ' · ' + m.phase;
    if (m.error.length > 0) {
      s = s + ' · ' + m.error;
    }
    return s;
  }

  private taskLeft(t: TeamTaskRow): string {
    return (t.subject.length > 0 ? t.subject : t.id) +
      (t.ownerName.length > 0 ? ' · ' + t.ownerName : '');
  }

  private subLeft(s: SubagentRow): string {
    return s.label.length > 0 ? s.label : s.id;
  }

  private subRight(s: SubagentRow): string {
    return s.mode.length > 0 ? s.mode : 'subagent';
  }

  build() {
    Column() {
      Text('智能团队')
        .fontSize(DsTypography.h4.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .width('100%')
      Text('成员 / 任务 / 子会话来自服务端 projections.values.agentTeam（只读展示）。')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelSecondary)
        .width('100%')
        .margin({ top: DsSpacing.liGap })
      Scroll() {
        Column() {
          if (this.team() === null) {
            Text('这个会话还没有智能团队数据。\n直接在聊天里发消息让负责人组建团队即可。')
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().labelSecondary)
              .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
              .width('100%')
          } else {
            this.teamRows()
          }
        }
        .width('100%')
      }
      .align(Alignment.Top)
      .width('100%')
      .margin({ top: DsSpacing.blockGap })
    }
    .width('100%')
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
      top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    .backgroundColor(this.c().bgLayer1)
  }

  @Builder
  teamRows() {
    Column() {
      if ((this.team() as AgentTeamProjection).failure !== null) {
        Text((this.team() as AgentTeamProjection).failure as string)
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().danger)
          .width('100%')
          .padding({ bottom: DsSpacing.liGap })
      }
      Text('成员（' + (this.team() as AgentTeamProjection).members.length.toString() + '）')
        .fontSize(DsTypography.smallStrong.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .width('100%')
        .padding({ top: DsSpacing.blockGap })
      ForEach((this.team() as AgentTeamProjection).members, (m: TeamMemberRow) => {
        this.pairRow(this.memberLeft(m), this.memberRight(m))
      }, (m: TeamMemberRow) => m.id)
      Text('任务（' + (this.team() as AgentTeamProjection).completedTasks.toString() + '/' +
        (this.team() as AgentTeamProjection).tasks.length.toString() + ' 完成）')
        .fontSize(DsTypography.smallStrong.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .width('100%')
        .padding({ top: DsSpacing.blockGap })
      ForEach((this.team() as AgentTeamProjection).tasks, (t: TeamTaskRow) => {
        this.pairRow(this.taskLeft(t), t.status)
      }, (t: TeamTaskRow) => t.id)
      Text('子会话（' + (this.team() as AgentTeamProjection).subagents.length.toString() + '）')
        .fontSize(DsTypography.smallStrong.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .width('100%')
        .padding({ top: DsSpacing.blockGap })
      ForEach((this.team() as AgentTeamProjection).subagents, (s: SubagentRow) => {
        this.pairRow(this.subLeft(s), this.subRight(s))
      }, (s: SubagentRow) => s.id)
      Blank().height(DsSpacing.blockGap)
      Flex({ wrap: FlexWrap.Wrap }) {
        Text('新建成员')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelPrimary)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
          .opacity(this.connected() ? 1 : 0.4)
          .onClick(() => {
            this.send('请新建一名团队成员，负责：');
          })
        Text('分配任务')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelPrimary)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
          .opacity(this.connected() ? 1 : 0.4)
          .onClick(() => {
            this.send('请给团队成员分配任务：');
          })
        Text('问进度')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelPrimary)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
          .opacity(this.connected() ? 1 : 0.4)
          .onClick(() => {
            this.send('汇报一下团队当前的成员状态和任务进度。');
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  pairRow(left: string, right: string) {
    Row() {
      Text(left)
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelSecondary)
        .layoutWeight(1)
      Text(right)
        .fontSize(DsTypography.smallStrong.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
    }
    .width('100%')
    .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
  }
}

@Component
export struct TodoSheet {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private todos(): TodoItem[] {
    const st: ChatStore | null = this.store;
    return st === null ? [] : todoItems(st.projections);
  }

  private completed(): number {
    let n: number = 0;
    for (const t of this.todos()) {
      if (t.isCompleted) {
        n++;
      }
    }
    return n;
  }

  build() {
    Column() {
      Text('待办任务')
        .fontSize(DsTypography.h4.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .width('100%')
      Text('列表来自服务端 projections.values.todos（只读展示，可能尚未产生）。')
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelSecondary)
        .width('100%')
        .margin({ top: DsSpacing.liGap })
      Scroll() {
        Column() {
          if (this.todos().length === 0) {
            Text('这个会话还没有待办任务。')
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().labelSecondary)
              .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
              .width('100%')
          } else {
            Row() {
              Text('进度')
                .fontSize(DsTypography.small.size)
                .fontColor(this.c().labelSecondary)
                .layoutWeight(1)
              Text('已完成 ' + this.completed().toString() + '/' + this.todos().length.toString())
                .fontSize(DsTypography.smallStrong.size)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c().labelPrimary)
            }
            .width('100%')
            .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
            ForEach(this.todos(), (t: TodoItem) => {
              Row({ space: DsSpacing.chipIconGap }) {
                Text(t.isCompleted ? '☑' : (t.isInProgress ? '🕑' : '☐'))
                  .fontSize(15)
                  .fontColor(t.isCompleted ? this.c().brand
                    : (t.isInProgress ? this.c().labelPrimary : this.c().labelTertiary))
                Text(t.content)
                  .fontSize(DsTypography.small.size)
                  .fontColor(this.c().labelPrimary)
                  .layoutWeight(1)
                Text(t.status)
                  .fontSize(DsTypography.caption.size)
                  .fontColor(t.isCompleted ? this.c().brand
                    : (t.isInProgress ? this.c().labelPrimary : this.c().labelTertiary))
              }
              .width('100%')
              .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
            }, (t: TodoItem) => t.content)
          }
        }
        .width('100%')
      }
      .align(Alignment.Top)
      .width('100%')
      .margin({ top: DsSpacing.blockGap })
    }
    .width('100%')
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
      top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    .backgroundColor(this.c().bgLayer1)
  }
}
