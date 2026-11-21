/**
 * 会话页溢出菜单（全屏遮层点任意处关闭；对照安卓 chat_page.dart 的 _OverflowMenu）。
 * 拆出 ChatView.ets 以守住单文件 ≤500 行（宪法 §7）。
 */

import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct ChatOverflowMenu {
  /** '1' 时多显示「代码工作视图」入口（设置④ dsh.codeWorkView）。 */
  @Prop codeWorkView: string = '0';
  onClose: (() => void) | null = null;
  onStats: (() => void) | null = null;
  onTrajectory: (() => void) | null = null;
  onCodeWork: (() => void) | null = null;
  onTeam: (() => void) | null = null;
  onTodo: (() => void) | null = null;
  onModel: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private fire(cb: (() => void) | null): void {
    if (cb !== null) {
      cb();
    }
  }

  build() {
    Column() {
      Column({ space: 4 }) {
        this.item('📊', '会话统计', this.onStats)
        this.item('🧭', '运行轨迹', this.onTrajectory)
        if (this.codeWorkView === '1') {
          this.item('🧩', '代码工作视图', this.onCodeWork)
        }
        this.item('🧠', '智能团队', this.onTeam)
        this.item('✅', '任务', this.onTodo)
        this.item('🎛️', '调整模型', this.onModel)
      }
      .width(190)
      .padding(6)
      .borderRadius(14)
      .backgroundColor(this.c().settingsSurface)
      .shadow({ radius: 18, color: this.c().shadow, offsetX: 0, offsetY: 4 })
      .margin({ right: DsSpacing.screenPad - 14, top: DsSpacing.topBarHeight })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.End)
    .justifyContent(FlexAlign.Start)
  }

  /** 带参 @Builder 不随 @State 刷新；这里参数与状态无关，只做静态行。 */
  @Builder
  item(icon: string, label: string, cb: (() => void) | null) {
    Row({ space: DsSpacing.chipIconGap }) {
      Text(icon)
        .fontSize(16)
      Text(label)
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .borderRadius(10)
    .accessibilityText('打开' + label)
    .onClick((): void => {
      const close = this.onClose;
      if (close !== null) {
        close();
      }
      this.fire(cb);
    })
  }
}
