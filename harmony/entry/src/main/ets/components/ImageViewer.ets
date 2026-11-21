/**
 * 全屏图片查看器（安卓 app/lib/ui/image_viewer.dart 口径）。
 *
 * 黑底 + 双指缩放/拖移，单击空白或右上关闭钮退出，双击在 1x/2.5x 间切换。
 * 图片字节已在 ImageTile 里解码成 PixelMap（零额外请求），这里只做手势与呈现。
 */

import { image } from '@kit.ImageKit';
import { window } from '@kit.ArkUI';

@Component
export struct ImageViewer {
  pixels: image.PixelMap | null = null;
  onClose: (() => void) | null = null;
  @State zoom: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State topInset: number = 0;
  private baseZoom: number = 1;

  aboutToAppear(): void {
    // bindContentCover 不含安全区：自己补状态栏高度，关闭钮才不被挡住。
    try {
      window.getLastWindow(this.getUIContext().getHostContext()).then((win: window.Window): void => {
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.topInset = px2vp(area.topRect.height);
      }).catch((): void => {
        // 拿不到就按 0 处理。
      });
    } catch (e) {
      // 非窗口环境（离屏预览）忽略。
    }
  }

  private close(): void {
    if (this.onClose !== null) {
      this.onClose();
    }
  }

  private reset(): void {
    this.zoom = 1;
    this.offsetX = 0;
    this.offsetY = 0;
  }

  private toggleZoom(): void {
    if (this.zoom > 1.5) {
      this.reset();
    } else {
      this.zoom = 2.5;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.pixels !== null) {
        Image(this.pixels)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .scale({ x: this.zoom, y: this.zoom })
          .translate({ x: this.offsetX, y: this.offsetY })
          .accessibilityText('大图')
      }
      // 单击关闭：只有原尺寸时生效，放大后单击留给拖移。
      Column()
        .width('100%')
        .height('100%')
        .onClick((): void => {
          if (this.zoom <= 1.01) {
            this.close();
          }
        })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart((): void => {
                this.baseZoom = this.zoom;
              })
              .onActionUpdate((event: GestureEvent): void => {
                const next: number = this.baseZoom * event.scale;
                this.zoom = next < 1 ? 1 : (next > 8 ? 8 : next);
              }),
            PanGesture({ fingers: 1 })
              .onActionUpdate((event: GestureEvent): void => {
                if (this.zoom > 1.01) {
                  this.offsetX = this.offsetX + event.offsetX;
                  this.offsetY = this.offsetY + event.offsetY;
                }
              }),
            TapGesture({ count: 2 })
              .onAction((): void => {
                this.toggleZoom();
              })
          )
        )
      Row() {
        Blank()
        Text('✕')
          .fontSize(22)
          .fontColor('#CCFFFFFF')
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .accessibilityText('关闭大图')
          .onClick((): void => {
            this.close();
          })
      }
      .width('100%')
      .padding({ top: this.topInset + 8, right: 8 })
      .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
