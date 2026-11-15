/**
 * 输入条 —— 对照安卓 composer.dart/composer_bar.dart（阶段 4 全功能）：
 * 斜杠命令补全面板 + @ 文件引用面板 + 图片（相册选图/魔数嗅探/8MiB 上限）
 * + 权限档位 chip（bindSheet 切换，danger-full-access 二次确认）
 * + 发送键三态（send/stop/disabled）+ 免责声明。
 * 命令/@ 面板壳在 ComposerPanels.ets。
 */

import { ChatStore } from '../core/ChatStore';
import { GatewayState } from '../core/GatewayEvents';
import { parseSlashDraft, parseAtMentionDraft, AtMentionDraft, SlashCommandList, SlashCommand,
  PromptPart } from '../core/Content';
import { GatewayRoot, GatewayEntry } from '../core/Files';
import { JsonMap } from '../core/JsonAccess';
import { PermissionSheet } from './PermissionSheet';
import { PickedImage, pickImageFromGallery } from '../platform/PhotoPick';
import { CommandPanel, AtFilePanel, AtEntry } from './ComposerPanels';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { common } from '@kit.AbilityKit';

type PanelMode = 'none' | 'cmd' | 'at';

@Component
export struct Composer {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @Prop version: number = 0;
  /** 受控草稿（发完清空）。 */
  @State draft: string = '';
  /** 光标位置（@ 片段解析用）。 */
  @State cursor: number = 0;
  @State panel: PanelMode = 'none';
  /** 斜杠命令缓存（切会话失效，同安卓 _commands/_commandsSid）。 */
  @State commands: SlashCommandList = SlashCommandList.empty();
  @State commandsSid: string = '';
  @State pendingImage: PickedImage | null = null;
  @State imageError: string = '';
  /** @ 面板状态。 */
  @State atDraft: AtMentionDraft | null = null;
  @State atEntries: AtEntry[] = [];
  @State atLoading: boolean = false;
  @State atFailed: boolean = false;
  @State atDir: string = '';
  private atRoots: GatewayRoot[] = []; // 授权根缓存
  @State permSheetOpen: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private st(): ChatStore | null {
    return this.store;
  }

  private connected(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.connectionState === GatewayState.READY;
  }

  private streaming(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.streaming;
  }

  private sid(): string {
    const st: ChatStore | null = this.store;
    return st === null ? '' : (st.sessionId ?? '');
  }

  private hasImage(): boolean {
    return this.pendingImage !== null && this.pendingImage.error.length === 0;
  }

  // ---------- 面板状态推导 ----------

  private onChanged(v: string): void {
    this.draft = v;
    this.updatePanel();
  }

  private updatePanel(): void {
    const slash = parseSlashDraft(this.draft);
    if (slash !== null && this.commands.commands.length > 0) {
      this.panel = 'cmd';
      this.atDraft = null;
      return;
    }
    const at = parseAtMentionDraft(this.draft, this.cursor);
    if (at !== null) {
      this.panel = 'at';
      this.atDraft = at;
      this.ensureAtEntries();
      return;
    }
    this.panel = 'none';
    this.atDraft = null;
  }

  /** 命令清单缓存（切会话失效；失败不落缓存，onChanged 自动重试）。 */
  private ensureCommands(): void {
    const st: ChatStore | null = this.store;
    const sid: string = this.sid();
    if (st === null || sid.length === 0 || this.commandsSid === sid) {
      return;
    }
    st.api.listCommands(sid).then((data: JsonMap): void => {
      this.commands = SlashCommandList.fromJson(data);
      this.commandsSid = sid;
      this.updatePanel();
    }).catch((): void => {
      // 失败不落缓存：下次输入自动重试（安卓口径）。
    });
  }

  /** @ 面板条目（多根合并 label/ 前缀 + query 前缀过滤；缓存根列表）。 */
  private ensureAtEntries(): void {
    const st: ChatStore | null = this.store;
    if (st === null || this.atDraft === null) {
      return;
    }
    const query: string = this.atDraft.query;
    if (this.atRoots.length === 0) {
      this.atLoading = true;
      st.api.listRootsRest().then((roots: GatewayRoot[]): void => {
        this.atRoots = roots;
        this.atLoading = false;
        this.loadAtEntries(query);
      }).catch((): void => {
        this.atLoading = false;
        this.atFailed = true;
      });
      return;
    }
    this.loadAtEntries(query);
  }

  private loadAtEntries(query: string): void {
    const st: ChatStore | null = this.store;
    if (st === null || this.atRoots.length === 0) {
      return;
    }
    this.atLoading = this.atEntries.length === 0;
    this.atFailed = false;
    const roots: GatewayRoot[] = this.atRoots;
    const dir: string = this.atDir;
    const jobs: Promise<GatewayEntry[]>[] = [];
    for (let i = 0; i < roots.length; i++) {
      jobs.push(st.api.listEntriesRest(roots[i].id, dir));
    }
    Promise.all(jobs).then((lists: GatewayEntry[][]): void => {
      const merged: AtEntry[] = [];
      for (let i = 0; i < lists.length; i++) {
        const label: string = roots.length > 1 ? roots[i].label + '/' : '';
        for (const e of lists[i]) {
          const name: string = label + e.path;
          if (query.length === 0 || name.toLowerCase().indexOf(query.toLowerCase()) === 0) {
            const item: AtEntry = new AtEntry();
            item.name = name;
            item.path = e.path;
            item.kind = e.kind;
            item.isDirectory = e.isDirectory;
            merged.push(item);
          }
        }
      }
      this.atEntries = merged;
      this.atLoading = false;
    }).catch((): void => {
      this.atLoading = false;
      this.atFailed = true;
    });
  }

  private applyCommand(cmd: SlashCommand): void {
    this.draft = '/' + cmd.name + ' ';
    this.panel = 'none';
  }

  private applyAtEntry(e: AtEntry): void {
    if (e.isDirectory) {
      this.atDir = e.path;
      this.loadAtEntries('');
      return;
    }
    const at: AtMentionDraft | null = this.atDraft;
    if (at === null) {
      return;
    }
    this.draft = this.draft.substring(0, at.start) + '@' + e.name + ' ' +
      this.draft.substring(at.end);
    this.panel = 'none';
    this.atDir = '';
  }

  private retryAt(): void {
    this.atRoots = [];
    this.atDir = '';
    this.ensureAtEntries();
  }

  // ---------- 发送 ----------

  private send(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    // 繁忙发送模式（设置页写 dshBusySend；缺省 queue）。
    const busyMode: string = AppStorage.get<string>('dshBusySend') ?? 'queue';
    const text: string = this.draft.trim();
    const img: PickedImage | null = this.pendingImage;
    this.draft = '';
    this.pendingImage = null;
    this.cursor = 0;
    this.panel = 'none';
    if (img !== null && img.error.length === 0) {
      st.sendWithImage(text, PromptPart.image(img.mediaType, img.base64, img.name), busyMode);
      return;
    }
    if (text.length === 0) {
      return;
    }
    if (parseSlashDraft(text) !== null) {
      st.runCommand(text);
      return;
    }
    st.send(text, undefined, busyMode);
  }

  private stop(): void {
    const st: ChatStore | null = this.store;
    if (st !== null) {
      st.cancelTurn();
    }
  }

  private pickImage(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    pickImageFromGallery(ctx).then((img: PickedImage | null): void => {
      if (img === null) {
        return;
      }
      this.imageError = img.error;
      if (img.error.length === 0) {
        this.pendingImage = img;
      }
    }).catch((): void => {
      this.imageError = '图片读取失败';
    });
  }

  @Builder
  permissionContent() {
    PermissionSheet({
      store: this.store,
      onDone: (m: string): void => {
        this.imageError = m;
      },
    })
  }

  // ---------- 渲染 ----------

  build() {
    Column() {
      if (this.lastError() !== null) {
        Text(this.lastError() as string)
          .fontSize(13)
          .fontColor(this.c().danger)
          .maxLines(2)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 6 })
      }
      if (this.imageError.length > 0) {
        Text(this.imageError)
          .fontSize(13)
          .fontColor(this.c().danger)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 6 })
          .onClick(() => {
            this.imageError = '';
          })
      }
      if (this.panel === 'cmd') {
        CommandPanel({
          commands: this.commands.matching(parseSlashDraft(this.draft)?.nameFragment ?? ''),
          onPick: (cmd: SlashCommand): void => this.applyCommand(cmd),
        })
      } else if (this.panel === 'at') {
        AtFilePanel({
          entries: this.atEntries,
          loading: this.atLoading,
          failed: this.atFailed,
          dirPath: this.atDir,
          onPick: (e: AtEntry): void => this.applyAtEntry(e),
          onRetry: (): void => this.retryAt(),
        })
      }
      TextArea({ text: this.draft, placeholder: '给 DSH 发送消息',
        controller: new TextAreaController() })
        .placeholderFont(DsTypography.inputPlaceholder)
        .fontColor(this.c().labelPrimary)
        .placeholderColor(this.c().inputHintText)
        .backgroundColor(this.c().inputFill)
        .borderRadius(22)
        .border({ width: 1, color: this.c().inputBorder })
        .fontSize(16)
        .caretColor(this.c().brand)
        .constraintSize({ minHeight: 44, maxHeight: 132 })
        .width('100%')
        .padding({ left: 14, right: 12, top: 11, bottom: 11 })
        .onChange((v: string) => {
          this.onChanged(v);
        })
        .onTextSelectionChange((start: number, end: number) => {
          this.cursor = start;
        })
        .enabled(this.connected())
      if (this.pendingImage !== null) {
        Row({ space: 6 }) {
          Text('🖼 ' + (this.pendingImage.name.length > 24
            ? this.pendingImage.name.substring(0, 24) : this.pendingImage.name))
            .fontSize(12)
            .fontColor(this.c().chipSelectedFg)
            .maxLines(1)
          Text('✕')
            .fontSize(12)
            .fontColor(this.c().labelTertiary)
            .onClick(() => {
              this.pendingImage = null;
            })
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(DsSpacing.chipRadius)
        .backgroundColor(this.c().chipSelectedBg)
        .margin({ top: 6 })
      }
      Row({ space: 8 }) {
        Text('🔒 ' + this.permissionLabel())
          .fontSize(12)
          .fontColor(this.c().chipSelectedFg)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
          .onClick(() => {
            this.permSheetOpen = true;
          })
        Blank()
        if (!this.streaming()) {
          Text('＋')
            .fontSize(18)
            .fontColor(this.hasImage() ? this.c().onBrand : this.c().labelSecondary)
            .width(DsSpacing.composerButtonSize)
            .height(DsSpacing.composerButtonSize)
            .borderRadius(12)
            .backgroundColor(this.hasImage() ? this.c().brand : Color.Transparent)
            .border({ width: 1.4, color: this.c().borderL2 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.pickImage();
            })
        }
        if (this.streaming()) {
          Button('停止', { type: ButtonType.Circle })
            .width(44)
            .height(44)
            .backgroundColor(this.c().brand)
            .fontColor(this.c().onBrand)
            .fontSize(13)
            .onClick(() => {
              this.stop();
            })
        } else {
          Button('↑', { type: ButtonType.Circle })
            .width(44)
            .height(44)
            .backgroundColor(this.sendEnabled() ? this.c().brand : this.c().inputFill)
            .fontColor(this.sendEnabled() ? this.c().onBrand : this.c().labelTertiary)
            .fontSize(18)
            .border({ width: this.sendEnabled() ? 0 : 1, color: this.c().borderL2 })
            .enabled(this.sendEnabled())
            .onClick(() => {
              this.send();
            })
        }
      }
      .width('100%')
      .margin({ top: 6 })
      .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 10 })
      if (!this.streaming()) {
        Text('回答由 AI 生成，仅供参考')
          .fontSize(11)
          .fontColor(this.c().labelTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ bottom: 6 })
      }
    }
    .bindSheet($$this.permSheetOpen, this.permissionContent(), {
      height: 320,
      showClose: false,
      backgroundColor: this.c().bgBase,
    })
  }

  private sendEnabled(): boolean {
    return (this.draft.trim() !== '' || this.hasImage()) && this.connected();
  }

  private permissionLabel(): string {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return '权限';
    }
    const v: string | null = st.currentPermission;
    return v === null ? '权限未设置' : v;
  }

  private lastError(): string | null {
    const st: ChatStore | null = this.store;
    return st === null ? null : st.lastError;
  }
}
