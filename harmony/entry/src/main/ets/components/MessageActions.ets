/**
 * 助手消息底部操作条 —— 对照安卓 message_actions.dart：
 * 复制 / 喜欢 / 朗读 / 分享 + 右侧「重新生成」。图标 17，间距 20，
 * labelTertiary 灰（线框风格），喜欢态 brand 色。
 */

import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { speak, stopSpeak } from '../platform/Tts';
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

  private speak(): void {
    speak(this.context(), this.text).then((ok: boolean): void => {
      this.hint = ok ? '正在朗读' : '朗读暂不可用';
      setTimeout((): void => {
        this.hint = '';
      }, 2000);
    }).catch((): void => {
      this.hint = '朗读暂不可用';
      setTimeout((): void => {
        this.hint = '';
      }, 2000);
    });
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

  @Builder
  icon(glyph: string, color: ResourceColor, tap: () => void) {
    Text(glyph)
      .fontSize(17)
      .fontColor(color)
      .padding({ right: DsSpacing.actionIconGap })
      .onClick(() => {
        tap();
      })
  }

  build() {
    Column() {
      Row() {
        this.icon(this.copied ? '✓' : '⧉', this.c().labelTertiary, (): void => {
          this.copy();
        })
        this.icon(this.liked ? '👍' : '👍', this.liked ? this.c().brand : this.c().labelTertiary,
          (): void => {
            this.liked = !this.liked;
          })
        this.icon('🔊', this.c().labelTertiary, (): void => {
          this.speak();
        })
        this.icon('⤴', this.c().labelTertiary, (): void => {
          this.share();
        })
        Blank()
        this.icon('⟳', this.c().labelTertiary, (): void => {
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
