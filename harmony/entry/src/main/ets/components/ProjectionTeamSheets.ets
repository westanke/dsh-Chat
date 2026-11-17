/**
 * 投影面板：智能团队 + 任务 —— 从 ProjectionSheets.ets 切出（单文件 ≤500 行）。
 * 对照安卓 projection_sheets.dart 的 TeamSheet / TodoSheet。全部本地只读，不发请求。
 */

import { ChatStore } from '../core/ChatStore';
import { TodoItem, todoItems, AgentTeamProjection, agentTeamProjectionOf,
  TeamMemberRow, TeamTaskRow, SubagentRow } from '../core/Projections';
import { GatewayState } from '../core/GatewayEvents';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

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
      Repeat<TeamMemberRow>((this.team() as AgentTeamProjection).members)
        .each((entry: RepeatItem<TeamMemberRow>) => {
          this.pairRow(this.memberLeft(entry.item), this.memberRight(entry.item))
        })
        .key((entry: TeamMemberRow) => entry.id)
      Text('任务（' + (this.team() as AgentTeamProjection).completedTasks.toString() + '/' +
        (this.team() as AgentTeamProjection).tasks.length.toString() + ' 完成）')
        .fontSize(DsTypography.smallStrong.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .width('100%')
        .padding({ top: DsSpacing.blockGap })
      Repeat<TeamTaskRow>((this.team() as AgentTeamProjection).tasks)
        .each((entry: RepeatItem<TeamTaskRow>) => {
          this.pairRow(this.taskLeft(entry.item), entry.item.status)
        })
        .key((entry: TeamTaskRow) => entry.id)
      Text('子会话（' + (this.team() as AgentTeamProjection).subagents.length.toString() + '）')
        .fontSize(DsTypography.smallStrong.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .width('100%')
        .padding({ top: DsSpacing.blockGap })
      Repeat<SubagentRow>((this.team() as AgentTeamProjection).subagents)
        .each((entry: RepeatItem<SubagentRow>) => {
          this.pairRow(this.subLeft(entry.item), this.subRight(entry.item))
        })
        .key((entry: SubagentRow) => entry.id)
      Blank().height(DsSpacing.blockGap)
      Flex({ wrap: FlexWrap.Wrap }) {
        Text('新建成员')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelPrimary)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
          .opacity(this.connected() ? 1 : 0.4)
          .accessibilityText('新建成员')
          .onClick(() => {
            this.send('请新建一名团队成员，负责：');
          })
        Text('分配任务')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelPrimary)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
          .opacity(this.connected() ? 1 : 0.4)
          .accessibilityText('分配任务')
          .onClick(() => {
            this.send('请给团队成员分配任务：');
          })
        Text('问进度')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelPrimary)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
          .opacity(this.connected() ? 1 : 0.4)
          .accessibilityText('问进度')
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

  /** 单条任务。抽 @Builder 让 Repeat 帧里只有一行调用（静态审计口径）。 */
  @Builder
  todoRow(t: TodoItem) {
    Row({ space: DsSpacing.chipIconGap }) {
      Text(t.isCompleted ? '☑' : (t.isInProgress ? '🕑' : '☐'))
        .fontSize(16)
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
  }

  build() {
    Column() {
      Text('任务')
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
            Text('任务清单为空')
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
            Repeat<TodoItem>(this.todos())
              .each((entry: RepeatItem<TodoItem>) => {
                this.todoRow(entry.item)
              })
              .key((entry: TodoItem) => entry.content)
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
