/**
 * 设置页「通用」分区 —— 官方通用设置四项（与 Flutter 端同规格）。
 *
 * 四项（PrefsStore 键存官方 token 字符串；AppStorage 键用无点驼峰，双写同源）：
 * 1. 工作步骤展示 dsh.workStepsDetail: concise|standard|detailed|verbose（默认 detailed）
 * 2. 工作步骤收起时机 dsh.collapseTiming: completion|next-input（默认 completion）
 * 3. 收起后显示的回复 dsh.foldedReplies: all|final（默认 all）—— verbose 时此行隐藏
 * 4. 显示代码工作视图 dsh.codeWorkView: '1'|'0'（默认 '0'）
 *
 * 生效路径（照 dshThemeMode 既有模式）：写 AppStorage + PrefsStore；
 * ChatView @Watch 把前两项解析后抄进 ChatStore.workSteps，MessageList 直接
 * @StorageProp 读第三项过滤，ChatView 读第四项控制溢出菜单入口。
 */

import { PrefsStore } from '../platform/PlatformBridge';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { parseWorkStepsDetail } from '../core/WorkSteps';

@Component
export struct SettingsGeneralSection {
  @StorageProp('dshDark') dark: boolean = false;
  /// 工作步骤展示档（官方 token 字符串；默认值与 core/WorkSteps 一致）。
  @StorageProp('dshWorkStepsDetail') workStepsDetail: string = 'detailed';
  @StorageProp('dshCollapseTiming') collapseTiming: string = 'completion';
  @StorageProp('dshFoldedReplies') foldedReplies: string = 'all';
  @StorageProp('dshCodeWorkView') codeWorkView: string = '0';

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private writePref(prefKey: string, appKey: string, value: string): void {
    AppStorage.setOrCreate(appKey, value);
    PrefsStore.putString(prefKey, value);
  }

  build() {
    Column() {
      Text('通用')
        .fontSize(DsTypography.caption.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().drawerGroupLabel)
        .width('100%')
        .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.liGap })

      // ① 工作步骤展示
      Column() {
        Text('工作步骤展示')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelPrimary)
          .width('100%')
          .padding({ bottom: DsSpacing.liGap })
        Text('选择希望看到多少工具调用细节')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
          .width('100%')
          .padding({ bottom: DsSpacing.liGap })
        Flex({ wrap: FlexWrap.Wrap }) {
          this.prefChip('dsh.workStepsDetail', 'dshWorkStepsDetail', 'concise', '简洁')
          this.prefChip('dsh.workStepsDetail', 'dshWorkStepsDetail', 'standard', '标准')
          this.prefChip('dsh.workStepsDetail', 'dshWorkStepsDetail', 'detailed', '详细')
          this.prefChip('dsh.workStepsDetail', 'dshWorkStepsDetail', 'verbose', '完全展开')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
        top: DsSpacing.settingsCardPadV, bottom: DsSpacing.settingsCardPadV })
      .borderRadius(DsSpacing.settingsCardRadius)
      .backgroundColor(this.c().settingsSurface)

      // ② 工作步骤收起时机
      Column() {
        Text('工作步骤收起时机')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelPrimary)
          .width('100%')
          .padding({ bottom: DsSpacing.liGap })
        Text('选择何时自动收起工作步骤')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
          .width('100%')
          .padding({ bottom: DsSpacing.liGap })
        Flex({ wrap: FlexWrap.Wrap }) {
          this.prefChip('dsh.collapseTiming', 'dshCollapseTiming', 'completion', '回答结束后')
          this.prefChip('dsh.collapseTiming', 'dshCollapseTiming', 'next-input', '下次有新消息时')
        }
        .width('100%')
      }
      .width('100%')
      .margin({ top: DsSpacing.settingsChipGap })
      .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
        top: DsSpacing.settingsCardPadV, bottom: DsSpacing.settingsCardPadV })
      .borderRadius(DsSpacing.settingsCardRadius)
      .backgroundColor(this.c().settingsSurface)

      // ③ 收起后显示的回复（verbose 档隐藏：全部展开时没有「收起后」可言）
      if (parseWorkStepsDetail(this.workStepsDetail) !== 'verbose') {
        Column() {
          Text('收起后显示的回复')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelPrimary)
            .width('100%')
            .padding({ bottom: DsSpacing.liGap })
          Text('工作步骤收起后，保留哪些助手回复')
            .fontSize(DsTypography.caption.size)
            .fontColor(this.c().labelTertiary)
            .width('100%')
            .padding({ bottom: DsSpacing.liGap })
          Flex({ wrap: FlexWrap.Wrap }) {
            this.prefChip('dsh.foldedReplies', 'dshFoldedReplies', 'all', '全部回复')
            this.prefChip('dsh.foldedReplies', 'dshFoldedReplies', 'final', '仅最终回答')
          }
          .width('100%')
        }
        .width('100%')
        .margin({ top: DsSpacing.settingsChipGap })
        .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
          top: DsSpacing.settingsCardPadV, bottom: DsSpacing.settingsCardPadV })
        .borderRadius(DsSpacing.settingsCardRadius)
        .backgroundColor(this.c().settingsSurface)
      }

      // ④ 显示代码工作视图（开关）
      Column() {
        Row() {
          Column() {
            Text('显示代码工作视图')
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().labelPrimary)
            Text('开启后，显示轨迹、本轮代码差异，可选择完整的 Agent 预设切换')
              .fontSize(DsTypography.caption.size)
              .fontColor(this.c().labelTertiary)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.codeWorkView === '1' })
            .selectedColor(this.c().brand)
            .onChange((on: boolean) => {
              this.writePref('dsh.codeWorkView', 'dshCodeWorkView', on ? '1' : '0');
            })
        }
        .width('100%')
        .padding({ top: DsSpacing.liGap, bottom: DsSpacing.liGap })
      }
      .width('100%')
      .margin({ top: DsSpacing.settingsChipGap })
      .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
        top: DsSpacing.settingsCardPadV, bottom: DsSpacing.settingsCardPadV })
      .borderRadius(DsSpacing.settingsCardRadius)
      .backgroundColor(this.c().settingsSurface)
    }
    .width('100%')
  }

  /** 分段选择 chip（沿用 busySend/sendChip 同款样式）。 */
  @Builder
  prefChip(prefKey: string, appKey: string, value: string, label: string) {
    Text(label)
      .fontSize(DsTypography.caption.size)
      .fontColor(this.selected(appKey, value)
        ? this.c().chipSelectedFg : this.c().labelSecondary)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .margin({ right: DsSpacing.settingsChipGap, bottom: DsSpacing.settingsChipGap })
      .borderRadius(DsSpacing.chipRadius)
      .backgroundColor(this.selected(appKey, value)
        ? this.c().chipSelectedBg : this.c().inputFill)
      .accessibilityText(label)
      .onClick(() => {
        this.writePref(prefKey, appKey, value);
      })
  }

  private selected(appKey: string, value: string): boolean {
    return AppStorage.get<string>(appKey) === value;
  }
}
