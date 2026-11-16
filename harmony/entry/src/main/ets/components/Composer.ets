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
  /** 同 MessageList：@Prop 必须带 @Watch 并把 store 派生值抄进 @State，否则
   * build 里读普通成员 store.streaming/currentPermission/lastError 不会重建。 */
  @Prop @Watch('syncVersion') version: number = 0;
  @State connectedView: boolean = false;
  @State streamingView: boolean = false;
  @State permView: string = '权限未设置';
  @State errView: string = '';
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
  /** 权限切换结果提示（成功/失败；点一下清除）。 */
  @State permHint: string = '';

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private st(): ChatStore | null {
    return this.store;
  }

  /** version 变化 → 重抄 store 派生值（@Prop @Watch 回调）。 */
  syncVersion(): void {
    const st: ChatStore | null = this.store;
    this.connectedView = st !== null && st.connectionState === GatewayState.READY;
    this.streamingView = st !== null && st.streaming;
    const perm: string | null = st === null ? null : st.currentPermission;
    this.permView = perm === null ? '权限未设置' : perm;
    this.errView = st === null || st.lastError === null ? '' : st.lastError;
  }

  aboutToAppear(): void {
    this.syncVersion();
  }

  private connected(): boolean {
    return this.connectedView;
  }

  private streaming(): boolean {
    return this.streamingView;
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
    // 命令清单按会话懒加载（切会话失效）；缺此调用会永远没有补全候选。
    this.ensureCommands();
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
        this.permHint = m;
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
      if (this.permHint.length > 0) {
        Text(this.permHint)
          .fontSize(13)
          .fontColor(this.c().labelSecondary)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 6 })
          .onClick(() => {
            this.permHint = '';
          })
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
      TextArea({ text: this.draft, placeholder: '发消息或创建任务，/ 调用指令，@ 文件或对话',
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
      // 底部行对齐官方输入框：左「＋」→ 权限 chip（盾牌 + 展开箭头），右发/停圆键。
      Row({ space: 8 }) {
        Text('＋')
          .fontSize(20)
          .fontColor(this.hasImage() ? this.c().onBrand : this.c().labelPrimary)
          .width(DsSpacing.composerButtonSize)
          .height(DsSpacing.composerButtonSize)
          .borderRadius(DsSpacing.composerButtonSize / 2)
          .backgroundColor(this.hasImage() ? this.c().brand : this.c().bgLayer1)
          .border({ width: 1, color: this.c().borderL1 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.pickImage();
          })
        Row({ space: 4 }) {
          Text('🛡')
            .fontSize(13)
            .fontColor(this.c().labelSecondary)
          Text(this.permissionLabel())
            .fontSize(13)
            .fontColor(this.c().labelSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('⌄')
            .fontSize(13)
            .fontColor(this.c().labelSecondary)
        }
        .constraintSize({ maxWidth: 200 })
        .onClick(() => {
          this.permSheetOpen = true;
        })
        Blank()
        if (this.streaming()) {
          Button('■', { type: ButtonType.Circle })
            .width(44)
            .height(44)
            .backgroundColor(this.c().brand)
            .fontColor(this.c().onBrand)
            .fontSize(15)
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
    return this.permView;
  }

  private lastError(): string | null {
    return this.errView.length === 0 ? null : this.errView;
  }
}
