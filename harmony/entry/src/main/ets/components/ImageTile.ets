/**
 * 消息图片块 —— 对照安卓 chat_image.dart 的 DsChatImage：
 * 历史图片引用自动下载（缓存走 store.fetchImageBytes）→ PixelMap → Image；
 * 占位（加载中转圈 / 失败显示错误 + 点按重试）；点按全屏预览。
 * 260 宽约束 + 圆角 codeBlockRadius，占位高 140。
 */

import { ChatStore } from '../core/ChatStore';
import { DsImageRef } from '../core/ImageRef';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { ImageViewer } from './ImageViewer';
import { mediaquery } from '@kit.ArkUI';
import { BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd } from '../core/Breakpoints';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
export struct ImageTile {
  store: ChatStore | null = null;
  ref: DsImageRef | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** 窗口宽度断点（R007 一多）：固定尺寸按档放大。 */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;
  @State pixels: image.PixelMap | null = null;
  @State loading: boolean = true;
  @State error: string = '';
  @State coverOpen: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** 窗口断点自读（R007 一多）：固定尺寸在宽屏放大一档。 */
  private refreshBreakpoint(): void {
    try {
      const md: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_MD);
      const lg: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_LG);
      const next: string = breakpointOf(md.matches, lg.matches);
      if (next !== this.bp) {
        this.bp = next;
        AppStorage.setOrCreate('dshBreakpoint', next);
      }
    } catch (e) {
      // 拿不到 mediaquery 时按手机档渲染。
    }
  }

  private atLeastMd(): boolean {
    return atLeastMd(this.bp);
  }

  aboutToAppear(): void {
    this.refreshBreakpoint();
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
      // createImageSource(buf: ArrayBuffer) —— 传 Uint8Array 会因类型不符返回
      // undefined（真机表现：Cannot read property createPixelMap of undefined），
      // 必须先取底层 buffer。
      const raw: ArrayBuffer = bytes.buffer as ArrayBuffer;
      const src: image.ImageSource | undefined = image.createImageSource(raw);
      if (src === undefined) {
        this.loading = false;
        this.error = '图片解码失败';
        return;
      }
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
          .width(this.atLeastMd() ? 320 : 260)
          .borderRadius(DsSpacing.codeBlockRadius)
          .accessibilityText('查看大图')
          .onClick(() => {
            this.coverOpen = true;
          })
      } else {
        Column({ space: 6 }) {
          if (this.loading) {
            LoadingProgress()
              .width(40)
              .height(40)
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
        .accessibilityText('图片加载失败，点按重试')
        .onClick(() => {
          if (!this.loading && this.error !== '') {
            this.reload();
          }
        })
      }
    }
    .bindContentCover(this.coverOpen, this.viewer(), {
      modalTransition: ModalTransition.DEFAULT,
      onDisappear: (): void => {
        this.coverOpen = false;
      }
    })
  }

  @Builder
  viewer() {
    ImageViewer({
      pixels: this.pixels,
      onClose: (): void => {
        this.coverOpen = false;
      }
    })
  }
}
