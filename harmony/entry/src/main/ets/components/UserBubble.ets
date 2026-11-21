/**
 * 用户消息气泡（从 MessageList 抽出，控单文件行数）：
 * 右对齐、最大宽 86.4%、左边距 32、内边距 16/12、圆角 16（§4.12 / 安卓
 * app/lib/ui/chat_message_items.dart）。
 */

import { ChatStore } from '../core/ChatStore';
import { DsImageRef, imageRefsOf, handoffRefOf } from '../core/ImageRef';
import { ContentImageRef } from '../core/Content';
import { DsColors, DsSpacing } from '../ui/theme';
import { ImageTile } from './ImageTile';

@Component
export struct UserBubble {
  store: ChatStore | null = null;
  @Prop text: string = '';
  /** 原始正文（清洗过的消息把「🖼️ 图片…」说明留在 rawText 里，交接图靠它）。 */
  @Prop rawText: string = '';
  @Prop images: ContentImageRef[] = [];
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private bubbleMaxWidth(): Length {
    return '86.4%';
  }

  private sidOf(): string {
    return this.store === null ? '' : (this.store.sessionId ?? '');
  }

  private rawOf(): string {
    return this.rawText !== '' ? this.rawText : this.text;
  }

  build() {
    Column({ space: 8 }) {
      if (this.images.length > 0) {
        Column() {
          ForEach(imageRefsOf(this.images), (r: DsImageRef) => {
            ImageTile({ store: this.store, ref: r, sid: this.sidOf() })
              .margin({ top: 4, bottom: 4 })
          }, (r: DsImageRef) => r.cacheKey)
        }
        .constraintSize({ maxWidth: this.bubbleMaxWidth() })
      }
      if (handoffRefOf(this.rawOf()) !== null) {
        ImageTile({ store: this.store, ref: handoffRefOf(this.rawOf()) as DsImageRef, sid: this.sidOf() })
          .constraintSize({ maxWidth: this.bubbleMaxWidth() })
      }
      Text(this.text === '' ? ' ' : this.text)
        .fontSize(16)
        .fontColor(this.c().labelPrimary)
        .lineHeight(24)
        .constraintSize({ maxWidth: this.bubbleMaxWidth() })
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor(this.c().userBubble)
        .borderRadius(DsSpacing.bubbleRadius)
    }
    .width('100%')
    .padding({ left: 32 })
    .alignItems(HorizontalAlign.End)
  }
}
