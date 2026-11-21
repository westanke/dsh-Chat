/**
 * 本轮生成文件卡（安卓 app/lib/ui/chat_artifact_card.dart 口径）。
 *
 * 数据来自 core/TurnChanges.turnArtifactsOf：本轮 write 新建的文件 + 最终回复里
 * 引用的本地文件。默认展示 4 行，超出可展开「全部 N 个文件」；行尾 ⋯ 弹
 * 复制路径 / 分享（系统分享面板）。
 */

import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { ArtifactFile, ARTIFACT_IMAGE, ARTIFACT_PDF, ARTIFACT_SLIDES, ARTIFACT_SPREADSHEET } from '../core/TurnChanges';
import { DsColors, DsSpacing, DsTypography } from '../ui/theme';
import { GatewayApi } from '../core/GatewayApi';
import { ResolvedFile } from '../core/Files';
import { shareText } from '../platform/Share';

/** Toast 停留时长（1500ms 是系统提示口径，不参与动效档位约束）。 */
const TOAST_MS: number = 1500;

@Component
export struct ArtifactCard {
  @Prop files: ArtifactFile[] = [];
  /** 取缩略图用（REST resolve + content；null 时只显示类型字形）。 */
  api: GatewayApi | null = null;
  @State expanded: boolean = false;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private shown(): ArtifactFile[] {
    if (this.expanded) {
      return this.files;
    }
    const out: ArtifactFile[] = [];
    for (let i = 0; i < this.files.length && i < DsSpacing.artifactCardMaxFiles; i++) {
      out.push(this.files[i]);
    }
    return out;
  }

  private copyPath(path: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, path);
    // Toast 停留时长（非动效，R017 对数字 duration 的提示在此豁免）。
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      promptAction.showToast({ message: '路径已复制', duration: TOAST_MS });
    }).catch((): void => {
      promptAction.showToast({ message: '复制失败', duration: TOAST_MS });
    });
  }

  private share(path: string): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    shareText(ctx, path).then((ok: boolean): void => {
      if (!ok) {
        promptAction.showToast({ message: '分享暂不可用', duration: TOAST_MS });
      }
    }).catch((): void => {
      promptAction.showToast({ message: '分享暂不可用', duration: TOAST_MS });
    });
  }

  build() {
    Column() {
      Row() {
        Text('▤')
          .fontSize(DsSpacing.changeCardIcon)
          .fontColor(this.c().labelSecondary)
          .margin({ top: 2 })
        Text('生成了 ' + this.files.length.toString() + ' 个文件')
          .fontSize(DsTypography.smallStrong.size)
          .fontWeight(DsTypography.smallStrong.weight)
          .lineHeight(DsTypography.smallStrong.lineHeight)
          .fontColor(this.c().labelPrimary)
          .margin({ left: 8 })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 6 })

      Repeat<ArtifactFile>(this.shown()).each((item: RepeatItem<ArtifactFile>) => {
        Row() {
          ArtifactThumb({ path: item.item.path, kind: item.item.kind, api: this.api })
          Column() {
            Text(item.item.name())
              .fontSize(DsTypography.small.size)
              .lineHeight(DsTypography.small.lineHeight)
              .fontColor(this.c().labelPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(item.item.caption())
              .fontSize(DsTypography.codeBlockLabel.size)
              .lineHeight(DsTypography.codeBlockLabel.lineHeight)
              .fontColor(this.c().labelTertiary)
              .maxLines(1)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 10 })
          Text('⋯')
            .fontSize(DsTypography.base.size)
            .fontColor(this.c().labelTertiary)
            .width(DsSpacing.cardActionSize)
            .height(DsSpacing.cardActionSize)
            .textAlign(TextAlign.Center)
            .accessibilityText('文件操作')
            .bindMenu([
              {
                value: '复制路径',
                action: (): void => {
                  this.copyPath(item.item.path);
                }
              },
              {
                value: '分享',
                action: (): void => {
                  this.share(item.item.path);
                }
              }
            ])
        }
        .width('100%')
        .padding({ left: 14, right: 6, top: 6, bottom: 6 })
        .onClick((): void => {
          this.copyPath(item.item.path);
        })
      }).key((f: ArtifactFile) => f.path)

      if (this.files.length > DsSpacing.artifactCardMaxFiles) {
        Row() {
          Text(this.expanded ? '收起' : '全部 ' + this.files.length.toString() + ' 个文件')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().brand)
          Text(this.expanded ? '⌃' : '⌄')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().brand)
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 10 })
        .onClick((): void => {
          this.expanded = !this.expanded;
        })
      } else {
        Blank().height(DsSpacing.cardFootGap)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.c().bgLayer1)
    .borderRadius(DsSpacing.changeCardRadius)
    .borderWidth(1)
    .borderColor(this.c().borderL2)
    .clip(true)
    .margin({ top: DsSpacing.chatGapCard })
  }
}

/**
 * 40×40 缩略图：图片走 REST resolve + content 读原始字节 → PixelMap；其余类型
 * 与加载失败都用类型字形占位（安卓 _Thumb 同款退路）。
 */
@Component
struct ArtifactThumb {
  @Prop path: string = '';
  @Prop kind: string = '';
  api: GatewayApi | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @State pixels: image.PixelMap | null = null;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private glyph(): string {
    if (this.kind === ARTIFACT_IMAGE) {
      return '▣';
    }
    if (this.kind === ARTIFACT_PDF) {
      return 'PDF';
    }
    if (this.kind === ARTIFACT_SPREADSHEET) {
      return '▦';
    }
    if (this.kind === ARTIFACT_SLIDES) {
      return '▤';
    }
    return '▢';
  }

  aboutToAppear(): void {
    if (this.kind !== ARTIFACT_IMAGE || this.api === null || this.path === '') {
      return;
    }
    const api: GatewayApi = this.api;
    const self: ArtifactThumb = this;
    api.resolvePathRest(this.path).then((resolved: ResolvedFile): Promise<Uint8Array> => {
      return api.readFileData(resolved.rootId, resolved.path);
    }).then((bytes: Uint8Array): void => {
      if (bytes.length === 0) {
        return;
      }
      const src: image.ImageSource | undefined = image.createImageSource(bytes.buffer as ArrayBuffer);
      if (src === undefined) {
        return;
      }
      src.createPixelMap().then((pm: image.PixelMap): void => {
        self.pixels = pm;
        src.release();
      }).catch((err: BusinessError): void => {
        src.release();
      });
    }).catch((): void => {
      // 路径不在授权根/文件已删/非图片：静默退回字形占位。
    });
  }

  build() {
    Stack() {
      if (this.pixels !== null) {
        Image(this.pixels)
          .width(DsSpacing.changeCardThumb)
          .height(DsSpacing.changeCardThumb)
          .objectFit(ImageFit.Cover)
          .borderRadius(DsSpacing.changeCardThumbRadius)
      } else {
        Text(this.glyph())
          .fontSize(this.kind === ARTIFACT_IMAGE ? 16 : 12)
          .fontColor(this.c().labelTertiary)
          .textAlign(TextAlign.Center)
          .width(DsSpacing.changeCardThumb)
          .height(DsSpacing.changeCardThumb)
          .backgroundColor(this.c().inputFill)
          .borderRadius(DsSpacing.changeCardThumbRadius)
          .borderWidth(1)
          .borderColor(this.c().borderL1)
      }
    }
    .width(DsSpacing.changeCardThumb)
    .height(DsSpacing.changeCardThumb)
  }
}
