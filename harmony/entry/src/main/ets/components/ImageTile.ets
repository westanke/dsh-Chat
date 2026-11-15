/**
 * 消息图片块 —— 对照安卓 chat_image.dart 的 DsChatImage：
 * 历史图片引用自动下载（缓存走 store.fetchImageBytes）→ PixelMap → Image；
 * 占位（加载中转圈 / 失败显示错误 + 点按重试）；点按全屏预览。
 * 260 宽约束 + 圆角 codeBlockRadius，占位高 140。
 */

import { ChatStore } from '../core/ChatStore';
import { DsImageRef } from '../core/ImageRef';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
export struct ImageTile {
  store: ChatStore | null = null;
  ref: DsImageRef | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @State pixels: image.PixelMap | null = null;
  @State loading: boolean = true;
  @State error: string = '';
  @State coverOpen: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    const st: ChatStore | null = this.store;
    const ref: DsImageRef | null = this.ref;
    if (st === null || ref === null) {
      this.loading = false;
      this.error = '图片引用缺失';
      return;
    }
    this.loading = true;
    this.error = '';
    st.fetchImageBytes(ref).then((bytes: Uint8Array): void => {
      const src: image.ImageSource = image.createImageSource(bytes);
      src.createPixelMap().then((pm: image.PixelMap): void => {
        this.pixels = pm;
        this.loading = false;
        src.release();
      }).catch((err: BusinessError): void => {
        this.loading = false;
        this.error = '图片解码失败';
        src.release();
      });
    }).catch((): void => {
      this.loading = false;
      this.error = '图片加载失败';
    });
  }

  build() {
    Stack() {
      if (this.pixels !== null) {
        Image(this.pixels)
          .objectFit(ImageFit.Cover)
          .width(260)
          .borderRadius(DsSpacing.codeBlockRadius)
          .onClick(() => {
            this.coverOpen = true;
          })
      } else {
        Column({ space: 6 }) {
          if (this.loading) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(this.c().labelTertiary)
          } else {
            Text('🖼')
              .fontSize(28)
              .fontColor(this.c().labelTertiary)
            Text(this.error === '' ? '图片' : this.error)
              .fontSize(DsTypography.caption.size)
              .fontColor(this.c().labelTertiary)
              .textAlign(TextAlign.Center)
            Text('点按重试')
              .fontSize(DsTypography.caption.size)
              .fontColor(this.c().link)
          }
        }
        .width(260)
        .height(140)
        .justifyContent(FlexAlign.Center)
        .borderRadius(DsSpacing.codeBlockRadius)
        .backgroundColor(this.c().mdCodeBlockBg)
        .onClick(() => {
          if (!this.loading && this.error !== '') {
            this.reload();
          }
        })
      }
      if (this.pixels !== null && this.coverOpen) {
        Image(this.pixels)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .onClick(() => {
            this.coverOpen = false;
          })
      }
    }
  }
}
