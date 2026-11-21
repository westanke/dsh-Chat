/**
 * 代码工作视图 sheet —— 通用设置④（dsh.codeWorkView）开启后，会话页溢出菜单
 * 新增「代码工作视图」入口。三段：
 * ①运行轨迹：内联复用 TrajectorySheet（showHeader=false，只留轨迹流）；
 * ②本轮代码差异：core/CodeDiff.codeDiffsOfLastTurn 从最后一轮 edit/write
 *   工具调用提取 ± 行，本地计算不发请求；
 * ③Agent 预设：GET /chat/agent-presets 列表 + PUT /chat/sessions/{sid}/agent-preset
 *   点选切换；非空白会话已锁定（首条消息后锁定），选项置灰；服务端 409
 *   （AGENT_PRESET_LOCKED）→ 行内提示兜底。
 *
 * 状态同步：预设镜像在 store.workSteps（ChatWorkSteps），AppStorage
 * dshExpandedVersion 每次 workSteps 变化都会 bump（ChatView.setNotify 写），
 * 本组件 @Watch 回读 —— 绕开 @Prop 经 bindSheet builder 传递不刷新的坑位。
 */
import { ChatStore } from '../core/ChatStore';
import { AgentPreset } from '../core/AgentPresets';
import {
  FileDiff, DiffLine, codeDiffsOfLastTurn, DIFF_LINE_ADD, DIFF_LINE_DEL, DIFF_KIND_WRITE,
} from '../core/CodeDiff';
import { RequestException } from '../core/GatewayEvents';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { TrajectorySheet } from './ProjectionSheets';

@Component
export struct CodeWorkSheet {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** workSteps 镜像版本（预设/当前预设变化都会 bump）→ 回读 store 快照。 */
  @StorageProp('dshExpandedVersion') @Watch('syncFromStore') workStepsVersion: number = 0;
  /** 0=运行轨迹 1=本轮代码差异 2=Agent 预设。 */
  @State segment: number = 0;
  @State presets: AgentPreset[] = [];
  /** 当前会话的预设 id（'' = 无）。 */
  @State currentPreset: string = '';
  /** 当前会话是否空白（首条消息前可切换预设）。 */
  @State blank: boolean = false;
  /** 本轮代码差异（切到第二段/挂载时重算）。 */
  @State diffs: FileDiff[] = [];
  /** 正在切换的预设 id（'' = 空闲）。 */
  @State busyId: string = '';
  /** 行内提示（409 / 锁定 / 切换结果）。 */
  @State hint: string = '';

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.syncFromStore();
    this.syncDiffs();
    const st: ChatStore | null = this.store;
    if (st !== null && st.workSteps.cachedAgentPresets().length === 0) {
      st.loadAgentPresets().catch((): void => {
        // 列表拉取失败不弹错：段内显示空态即可。
      });
    }
  }

  private syncFromStore(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      this.presets = [];
      this.currentPreset = '';
      this.blank = false;
      return;
    }
    this.presets = st.workSteps.cachedAgentPresets();
    const current: string | null = st.workSteps.currentAgentPreset();
    if (current !== null && current !== '') {
      this.currentPreset = current;
    } else {
      // 无本地镜像（新进会话）：回退 sessions 列表里的 agentPreset 字段。
      let found: string = '';
      for (const s of st.sessions) {
        if (s.id === st.sessionId && s.agentPreset !== null) {
          found = s.agentPreset as string;
        }
      }
      this.currentPreset = found;
    }
    // blank：无会话（首条消息未发）或会话 blank=true 都算可切换。
    let sessionBlank: boolean = true;
    for (const s of st.sessions) {
      if (s.id === st.sessionId) {
        sessionBlank = s.blank;
      }
    }
    this.blank = st.sessionId === null || st.sessionId === '' || sessionBlank;
  }

  private syncDiffs(): void {
    const st: ChatStore | null = this.store;
    this.diffs = st === null ? [] : codeDiffsOfLastTurn(st.messages);
  }

  private pickSegment(v: number): void {
    this.segment = v;
    if (v === 1) {
      this.syncDiffs();
    }
  }

  /** 点选预设：空白会话直接 PUT；409/锁定走行内提示（UI 不关 sheet）。 */
  private selectPreset(p: AgentPreset): void {
    if (this.busyId !== '') {
      return;
    }
    if (!this.blank) {
      this.hint = '首条消息后锁定，仅空白会话可切换';
      return;
    }
    if (!p.available) {
      this.hint = '该预设当前不可用';
      return;
    }
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    if (st.sessionId === null || st.sessionId === '') {
      this.hint = '先发送第一条消息创建会话';
      return;
    }
    this.busyId = p.id;
    this.hint = '';
    st.selectAgentPreset(p.id).then((applied: string): void => {
      this.busyId = '';
      const name: string = this.presetNameById(applied);
      this.hint = name === '' ? '已切换 Agent 预设' : '已切换到「' + name + '」';
    }).catch((err: Object): void => {
      this.busyId = '';
      const locked: boolean = err instanceof RequestException
        && (err as RequestException).code === 'AGENT_PRESET_LOCKED';
      this.hint = locked ? '已锁定，仅空白会话可切换' : '切换失败，请稍后重试';
    });
  }

  private presetNameById(id: string): string {
    for (const p of this.presets) {
      if (p.id === id) {
        return p.name;
      }
    }
    return '';
  }

  /** 行是否可点（空白会话且预设可用）。 */
  private rowEnabled(p: AgentPreset): boolean {
    return this.blank && p.available && this.busyId === '';
  }

  private rowOpacity(p: AgentPreset): number {
    return this.rowEnabled(p) ? 1 : 0.55;
  }

  private rowBg(p: AgentPreset): string {
    return this.currentPreset === p.id ? this.c().chipSelectedBg : this.c().bgLayer1;
  }

  build() {
    Column() {
      // 三段切换 chips（触控热区 40vp，R009）。
      Row({ space: 8 }) {
        this.segmentChip('运行轨迹', 0)
        this.segmentChip('本轮代码差异', 1)
        this.segmentChip('Agent 预设', 2)
      }
      .width('100%')
      .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, top: DsSpacing.blockGap })
      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().settingsWarnFg)
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .margin({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, top: 8 })
          .borderRadius(8)
          .backgroundColor(this.c().settingsWarnBg)
      }
      if (this.segment === 0) {
        Column() {
          Text('按轮次查看消息、工具调用、耗时和 Token 等运行记录。')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelSecondary)
            .width('100%')
            .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
              top: DsSpacing.blockGap })
          TrajectorySheet({ store: this.store, showHeader: false })
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.segment === 1) {
        this.diffSegment()
      } else {
        this.presetSegment()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.c().bgBase)
  }

  @Builder
  segmentChip(label: string, value: number) {
    Text(label)
      .fontSize(DsTypography.caption.size)
      .fontColor(this.segment === value ? this.c().chipSelectedFg : this.c().labelSecondary)
      .height(DsSpacing.todoRowHeight)
      .padding({ left: 12, right: 12 })
      .borderRadius(DsSpacing.chipRadius)
      .backgroundColor(this.segment === value ? this.c().chipSelectedBg : this.c().inputFill)
      .accessibilityText(label + (this.segment === value ? '，当前段' : ''))
      .onClick((): void => {
        this.pickSegment(value);
      })
  }

  /** 第二段：本轮代码差异（edit/write 工具调用 → ± 行）。 */
  @Builder
  diffSegment() {
    Scroll() {
      Column() {
        Text('由最后一轮的写文件与改文件调用本地提取，不产生网络请求。')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelSecondary)
          .width('100%')
        if (this.diffs.length === 0) {
          Text('本轮还没有代码改动。')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelTertiary)
            .width('100%')
            .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
        }
        Repeat<FileDiff>(this.diffs).each((item: RepeatItem<FileDiff>) => {
          this.diffCard(item.item)
        }).key((d: FileDiff) => d.path + '-' + d.kind + '-' + d.lines.length.toString())
      }
      .width('100%')
      .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
        top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    }
    .align(Alignment.Top)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  diffCard(d: FileDiff) {
    Column() {
      Row({ space: DsSpacing.chipIconGap }) {
        Text('📄')
          .fontSize(12)
        Text(d.path)
          .fontSize(DsTypography.codeBlockLabel.size)
          .fontFamily('monospace')
          .fontColor(this.c().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(d.kind === DIFF_KIND_WRITE ? '新增' : '修改')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().chipSelectedFg)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      if (d.lines.length > 0) {
        Column() {
          Repeat<DiffLine>(d.lines).each((item: RepeatItem<DiffLine>) => {
            Row({ space: 4 }) {
              Text(item.item.type === DIFF_LINE_ADD ? '+' : (item.item.type === DIFF_LINE_DEL ? '-' : ' '))
                .fontSize(DsTypography.codeBlockLabel.size)
                .fontFamily('monospace')
                .fontColor(this.lineFg(item.item))
                .width(DsSpacing.diffPrefixWidth)
              Text(item.item.text === '' ? ' ' : item.item.text)
                .fontSize(DsTypography.codeBlockLabel.size)
                .fontFamily('monospace')
                .fontColor(this.lineFg(item.item))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: DsSpacing.settingsChipGap, right: DsSpacing.settingsChipGap })
            .backgroundColor(this.lineBg(item.item))
          }).key((l: DiffLine) => l.type + '-' + l.text)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: DsSpacing.blockGap })
    .borderRadius(DsSpacing.codeBlockRadius)
    .borderWidth(1)
    .borderColor(this.c().inputBorder)
    .backgroundColor(this.c().bgLayer1)
  }

  private lineFg(l: DiffLine): string {
    if (l.type === DIFF_LINE_ADD) {
      return this.c().diffAddFg;
    }
    if (l.type === DIFF_LINE_DEL) {
      return this.c().diffDelFg;
    }
    return this.c().labelTertiary;
  }

  private lineBg(l: DiffLine): string {
    if (l.type === DIFF_LINE_ADD) {
      return this.c().diffAddBg;
    }
    if (l.type === DIFF_LINE_DEL) {
      return this.c().diffDelBg;
    }
    return this.c().bgLayer1;
  }

  /** 第三段：Agent 预设列表（当前项打勾；非空白会话置灰 + 锁定说明）。 */
  @Builder
  presetSegment() {
    Scroll() {
      Column() {
        if (!this.blank) {
          Text('首条消息后锁定：Agent 预设只能在空白会话切换。')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelSecondary)
            .width('100%')
            .padding({ top: DsSpacing.blockGap })
        }
        if (this.presets.length === 0) {
          Text(this.busyId === '' ? '预设列表加载中…' : '正在切换…')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelTertiary)
            .width('100%')
            .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
        }
        Repeat<AgentPreset>(this.presets).each((item: RepeatItem<AgentPreset>) => {
          this.presetRow(item.item)
        }).key((p: AgentPreset) => p.id + '-' + (this.currentPreset === p.id ? '1' : '0'))
      }
      .width('100%')
      .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
        bottom: DsSpacing.blockGap })
    }
    .align(Alignment.Top)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  presetRow(p: AgentPreset) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(p.name)
            .fontSize(DsTypography.smallStrong.size)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c().labelPrimary)
          if (p.isDefault) {
            Text('默认')
              .fontSize(DsTypography.caption.size)
              .fontColor(this.c().chipSelectedFg)
              .padding({ left: DsSpacing.settingsChipGap, right: DsSpacing.settingsChipGap })
              .borderRadius(DsSpacing.chipRadius)
              .backgroundColor(this.c().chipSelectedBg)
          }
        }
        .alignItems(VerticalAlign.Center)
        if (p.description !== null && (p.description as string) !== '') {
          Text(p.description as string)
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelSecondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.currentPreset === p.id) {
        Text('✓')
          .fontSize(16)
          .fontColor(this.c().brand)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .margin({ top: 8 })
    .borderRadius(10)
    .backgroundColor(this.rowBg(p))
    .borderWidth(this.currentPreset === p.id ? 1 : 0)
    .borderColor(this.c().brand)
    .opacity(this.rowOpacity(p))
    .accessibilityText('Agent 预设 ' + p.name + (this.currentPreset === p.id ? '，当前预设' : ''))
    .onClick((): void => {
      this.selectPreset(p);
    })
  }
}
