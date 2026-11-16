/**
 * 助手消息底部操作条 —— 对照安卓 message_actions.dart：
 * 复制 / 喜欢 / 朗读 / 分享 + 右侧「重新生成」。图标 17，间距 20，
 * labelTertiary 灰（线框风格），喜欢态 brand 色。
 */

import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { speak, stopSpeak, addSpeakingWatcher, removeSpeakingWatcher } from '../platform/Tts';
import { shareText } from '../platform/Share';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct MessageActions {
  @StorageProp('dshDark') dark: boolean = false;
  text: string = '';
  sentAt: number | null = null;
  onRegenerate: (() => void) | null = null;
  @State liked: boolean = false;
  @State copied: boolean = false;
  @State hint: string = '';
  /** 本条消息正在朗读（🔊 变 ⏹，再点一次停止）。 */
  @State speaking: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private copy(): void {
    const pasteData: pasteboard.PasteData = pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN, this.text);
    pasteboard.getSystemPasteboard().setData(pasteData).then((): void => {
      this.copied = true;
      setTimeout((): void => {
        this.copied = false;
      }, 2000);
    }).catch((): void => {
    });
  }

  /** 自己注册的观察者引用（注销时要传同一个函数）。 */
  private watcher: (busy: boolean) => void = (busy: boolean): void => {
    if (!busy && this.speaking) {
      this.speaking = false;
    }
  };

  aboutToAppear(): void {
    addSpeakingWatcher(this.watcher);
  }

  aboutToDisappear(): void {
    removeSpeakingWatcher(this.watcher);
  }

  private toggleSpeak(): void {
    if (this.speaking) {
      stopSpeak();
      this.speaking = false;
      this.flash('已停止朗读');
      return;
    }
    speak(this.context(), this.text).then((ok: boolean): void => {
      this.speaking = ok;
      this.flash(ok ? '正在朗读' : '朗读暂不可用');
    }).catch((): void => {
      this.speaking = false;
      this.flash('朗读暂不可用');
    });
  }

  private flash(msg: string): void {
    this.hint = msg;
    setTimeout((): void => {
      this.hint = '';
    }, 2000);
  }

  private share(): void {
    // 分享文本尾部附发送时间（安卓第四轮反馈 7 口径）。
    let body: string = this.text;
    const at: number | null = this.sentAt;
    if (at !== null && at > 0) {
      body = body + '\n\n—— 发送于 ' + formatSentTime(at);
    }
    shareText(this.context(), body).then((ok: boolean): void => {
      if (!ok) {
        this.hint = '分享暂不可用';
        setTimeout((): void => {
          this.hint = '';
        }, 2000);
      }
    }).catch((): void => {
      this.hint = '分享暂不可用';
      setTimeout((): void => {
        this.hint = '';
      }, 2000);
    });
  }

  /**
   * 操作图标全部内联，**不走 @Builder**：ArkUI 的 @Builder 只要带参数
   * （哪怕只是稳定的 id 字符串），参数不变时就不会重跑，builder 内部读
   * @State 也取不到新值 —— 点朗读后提示已出现、图标却停在 🔊 不变
   * （真机实证两轮：先试按值传 glyph/color，再试传稳定 id，都不刷新）。
   * 只有把 Text 直接写进 build() 才会随 @State 重算。
   */

  build() {
    Column() {
      Row() {
        Text(this.copied ? '✓' : '⧉')
          .fontSize(16)
          .fontColor(this.c().labelTertiary)
          .padding({ right: DsSpacing.actionIconGap })
          .accessibilityText(this.copied ? '已复制' : '复制回答')
          .onClick(() => {
            this.copy();
          })
        Text('👍')
          .fontSize(16)
          .fontColor(this.liked ? this.c().brand : this.c().labelTertiary)
          .padding({ right: DsSpacing.actionIconGap })
          .accessibilityText(this.liked ? '取消喜欢' : '喜欢')
          .onClick(() => {
            this.liked = !this.liked;
          })
        Text(this.speaking ? '⏹' : '🔊')
          .fontSize(16)
          .fontColor(this.speaking ? this.c().brand : this.c().labelTertiary)
          .padding({ right: DsSpacing.actionIconGap })
          .accessibilityText(this.speaking ? '停止朗读' : '朗读回答')
          .onClick(() => {
            this.toggleSpeak();
          })
        Text('⤴')
          .fontSize(16)
          .fontColor(this.c().labelTertiary)
          .padding({ right: DsSpacing.actionIconGap })
          .accessibilityText('分享回答')
          .onClick(() => {
            this.share();
          })
        Blank()
        Text('⟳')
          .fontSize(16)
          .fontColor(this.c().labelTertiary)
          .padding({ right: DsSpacing.actionIconGap })
          .accessibilityText('重新生成')
          .onClick(() => {
            if (this.onRegenerate !== null) {
              this.onRegenerate();
            }
          })
      }
      .width('100%')
      .margin({ top: 10, bottom: 4 })
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
          .width('100%')
          .padding({ top: 2, bottom: 4 })
      }
    }
    .width('100%')
  }
}

/// epochMs → 'yyyy-MM-dd HH:mm'（安卓 formatSentTime 同口径，无依赖）。
function pad(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

function formatSentTime(ms: number): string {
  const d: Date = new Date(ms);
  return d.getFullYear().toString() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
    ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}
