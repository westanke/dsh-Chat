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
import { permissionLabelOf } from '../core/Permissions';
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
    // 服务端原始值是 read-only/workspace-write/danger-full-access 之类的 ASCII 档位名，
    // 界面一律显示中文标签（permissionLabelOf 未识别时原样返回，不杜撰档位）。
    this.permView = permissionLabelOf(perm);
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
    // 光标兜底：onChange 先于 onTextSelectionChange 触发，刚敲下 '@' 那一帧
    // this.cursor 还停在上一次的位置（初值 0），parseAtMentionDraft('@', 0)
    // 永远返回 null —— 面板要等下一次输入才弹。输入必然把光标推到插入点之后，
    // 这里按「末尾」估一次先算面板；随后 onTextSelectionChange 拿真位置再校正。
    this.cursor = v.length;
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
    // 逐根拉取并各自容错：某个根下没有同名子目录（404）不该拖垮整张面板
    // （实测：下钻到 workspace/.dhs-diff 时另两个根 404 → Promise.all 整批 reject
    //  → 面板显示「目录加载失败」）。全失败才算失败。
    const jobs: Promise<GatewayEntry[]>[] = [];
    for (let i = 0; i < roots.length; i++) {
      jobs.push(st.api.listEntriesRest(roots[i].id, dir)
        .catch((e: Error): GatewayEntry[] => new Array<GatewayEntry>()));
    }
    Promise.all(jobs).then((lists: GatewayEntry[][]): void => {
      const merged: AtEntry[] = [];
      let okRoots: number = 0;
      for (let i = 0; i < lists.length; i++) {
        const label: string = roots.length > 1 ? roots[i].label + '/' : '';
        if (lists[i].length > 0 || dir.length === 0) {
          okRoots = okRoots + 1;
        }
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
      if (okRoots === 0 && dir.length > 0) {
        this.atFailed = true; // 所有根都没这个目录：确实失败
      }
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
          .fontSize(12)
          .fontColor(this.c().danger)
          .maxLines(2)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 6 })
          .accessibilityText('错误提示，点按查看')
      }
      if (this.permHint.length > 0) {
        Text(this.permHint)
          .fontSize(12)
          .fontColor(this.c().labelSecondary)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 6 })
          .accessibilityText('权限提示，点按关闭')
          .onClick(() => {
            this.permHint = '';
          })
      }
      if (this.imageError.length > 0) {
        Text(this.imageError)
          .fontSize(12)
          .fontColor(this.c().danger)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 6 })
          .accessibilityText('图片错误提示，点按关闭')
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
      // 官方输入框：文本框 + 底部按钮行（＋ / 权限 / 发送）共处一个圆角容器内。
      Column({ space: 0 }) {
      TextArea({ text: this.draft, placeholder: '发消息或创建任务，/ 调用指令，@ 文件或对话',
        controller: new TextAreaController() })
        .placeholderFont(DsTypography.inputPlaceholder)
        .fontColor(this.c().labelPrimary)
        .placeholderColor(this.c().inputHintText)
        .backgroundColor(Color.Transparent)
        // ArkUI TextArea 默认圆角 20；这里要跟外层胶囊贴合走直角，取最小合法档 2
        //（R003 的圆角档位不含 0）。
        .borderRadius(2)
        .fontSize(16)
        .caretColor(this.c().brand)
        .constraintSize({ minHeight: 44, maxHeight: 120 })
        .width('100%')
        .padding({ left: 6, right: 6, top: 12, bottom: 2 })
        .onChange((v: string) => {
          this.onChanged(v);
        })
        .onTextSelectionChange((start: number, end: number) => {
          // 光标真值回填：与 onChange 的「末尾估计」不同才重算面板
          // （中途点击/方向键移动光标时，@ 片段解析依赖真实位置）。
          if (start !== this.cursor) {
            this.cursor = start;
            this.updatePanel();
          }
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
            .accessibilityText('移除待发送图片')
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
          .accessibilityText('添加图片')
          .onClick(() => {
            this.pickImage();
          })
        Row({ space: 4 }) {
          Text('🛡')
            .fontSize(12)
            .fontColor(this.c().labelSecondary)
          Text(this.permissionLabel())
            .fontSize(12)
            .fontColor(this.c().labelSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('⌄')
            .fontSize(12)
            .fontColor(this.c().labelSecondary)
        }
        .constraintSize({ maxWidth: 200 })
        .accessibilityText('会话权限：' + this.permissionLabel())
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
            .fontSize(16)
            .accessibilityText('停止生成')
            .onClick(() => {
              this.stop();
            })
        } else {
          // 发送键对齐官方：实心品牌色圆 + 白色向上箭头（字号 20、加粗，官方图标是
          // 线宽较粗的 arrow-up）；禁用态浅灰底 + 中灰箭头，不再用纯白底（
          // 白底 + 浅灰箭头在浅色主题下几乎看不见，2026-11-16 用户反馈）。
          Button('↑', { type: ButtonType.Circle })
            .width(44)
            .height(44)
            .backgroundColor(this.sendEnabled() ? this.c().brand : this.c().sendDisabledBg)
            .fontColor(this.sendEnabled() ? this.c().onBrand : this.c().sendDisabledFg)
            .fontSize(20)
            .fontWeight(this.sendEnabled() ? FontWeight.Bold : FontWeight.Medium)
            .enabled(this.sendEnabled())
            .accessibilityText(this.sendEnabled() ? '发送' : '发送（未就绪）')
            .onClick(() => {
              this.send();
            })
        }
      }
      .width('100%')
      .margin({ top: 2 })
      .padding({ left: 2, right: 2, bottom: 2 })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 8 })
      .backgroundColor(this.c().inputFill)
      .borderRadius(24)
      .border({ width: 1, color: this.c().inputBorder })
      .margin({ left: DsSpacing.screenPad, right: DsSpacing.screenPad })
      if (!this.streaming()) {
        Text('回答由 AI 生成，仅供参考')
          .fontSize(10)
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
