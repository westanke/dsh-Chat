/**
 * 输入条 —— 对照安卓 composer.dart/composer_bar.dart：斜杠命令补全 + @ 文件
 * 引用面板（含「选择项目中的内容」入口）+ 图片 chip + 权限档位 chip
 * （bindSheet 二次确认）+ 发送键三态 + 免责声明；面板壳在 ComposerPanels.ets。
 */
import { ChatStore } from '../core/ChatStore';
import { GatewayState } from '../core/GatewayEvents';
import { parseSlashDraft, parseAtMentionDraft, AtMentionDraft, SlashCommandList, SlashCommand,
  PromptPart } from '../core/Content';
import { GatewayRoot } from '../core/Files';
import { JsonMap } from '../core/JsonAccess';
import { PermissionSheet } from './PermissionSheet';
import { PickedImage, pickImageFromGallery } from '../platform/PhotoPick';
import { ImageChips } from './ImageChips';
import { ComposerActions } from './ComposerActions';
import { CommandPanel, AtFilePanel } from './ComposerPanels';
import { ErrorBanner, HintBanner } from './ComposerBanners';
import { AtEntry, AtSessionHit, AtMentionMerge, loadMergedAtEntries, inSubDirectory,
  sessionMatches, insertSessionMention, atLeafQuery, atQueryDir, joinAtDir } from '../core/AtMention';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { permissionLabelOf } from '../core/Permissions';
import { common } from '@kit.AbilityKit';
import { mediaquery } from '@kit.ArkUI';
import { BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd, floatingColumnWidth } from '../core/Breakpoints';

type PanelMode = 'none' | 'cmd' | 'at';

@Component
export struct Composer {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** 窗口断点（R007）：输入区高度与按键尺寸按档放大；列宽另读 dshColumnWidthVp。 */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;
  /** 同 MessageList：@Prop 必须带 @Watch 并把 store 派生值抄进 @State，否则 build 里读普通成员（streaming / currentPermission / lastError）不会重建。 */
  @Prop @Watch('syncVersion') version: number = 0;
  @StorageProp('dshColumnWidthVp') columnWidth: number = 0;
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
  /** 待发送图片（一条最多 6 张，安卓同口径）。 */
  @State pendingImages: PickedImage[] = [];
  @State imageError: string = '';
  /** @ 面板状态。 */
  @State atDraft: AtMentionDraft | null = null;
  @State atEntries: AtEntry[] = [];
  @State atLoading: boolean = false;
  @State atFailed: boolean = false;
  @State atDir: string = '';
  @State atSessions: AtSessionHit[] = [];
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

  /** 窗口断点自读（R007 一多）：输入区与按键在宽屏放大一档。 */
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
      // 拿不到 mediaquery 时按手机档渲染，不阻塞输入。
    }
  }

  private atLeastMd(): boolean {
    return atLeastMd(this.bp);
  }

  aboutToAppear(): void {
    this.refreshBreakpoint();
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

  private hasPending(): boolean {
    return this.pendingImages.length > 0;
  }

  private pendingNames(): string[] {
    const out: string[] = [];
    for (const img of this.pendingImages) {
      out.push(img.name);
    }
    return out;
  }

  /** ---------- 面板状态推导 ---------- */
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
      const st: ChatStore | null = this.store;
      this.atSessions = sessionMatches(st === null ? [] : st.sessions,
        st === null ? null : st.sessionId, atLeafQuery(at.query));
      this.ensureAtEntries();
      return;
    }
    this.panel = 'none';
    this.atDraft = null;
    this.atSessions = [];
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
    // 取数与合并下沉 core/AtMention.loadMergedAtEntries（逐根容错、多根才带
    // label/ 前缀）：Composer 只做状态搬运。
    const dir: string = joinAtDir(this.atDir, atQueryDir(query));
    loadMergedAtEntries(st.api, this.atRoots, dir, atLeafQuery(query))
      .then((merged: AtMentionMerge): void => {
        this.atEntries = merged.items;
        this.atLoading = false;
        this.atFailed = merged.okRoots === 0 && inSubDirectory(this.atDir);
      })
      .catch((): void => {
        this.atLoading = false;
        this.atFailed = true;
      });
  }

  private applySession(h: AtSessionHit): void {
    const at: AtMentionDraft | null = this.atDraft;
    if (at === null) {
      return;
    }
    this.draft = insertSessionMention(this.draft, at, h.id, h.title);
    this.panel = 'none';
    this.atDraft = null;
    this.atSessions = [];
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

  /** 「选择项目中的内容」：合成空 @ 草稿（query=''）复用 @ 目录面板，选中后原位插入。 */
  private openProjectPanel(): void {
    const at: number = this.draft.length;
    const synthetic: AtMentionDraft = { query: '', start: at, end: at };
    this.atDraft = synthetic;
    this.cursor = at;
    this.panel = 'at';
    this.ensureAtEntries();
  }

  /** 发送：busyMode 读 dshBusySend（缺省 queue）。 */
  private send(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    const busyMode: string = AppStorage.get<string>('dshBusySend') ?? 'queue';
    const text: string = this.draft.trim();
    const images: PickedImage[] = this.pendingImages;
    this.draft = '';
    this.pendingImages = [];
    this.cursor = 0;
    this.panel = 'none';
    if (images.length > 0) {
      const parts: PromptPart[] = [];
      for (const img of images) {
        parts.push(PromptPart.image(img.mediaType, img.base64, img.name));
      }
      st.send(text, parts, busyMode);
      return;
    }
    const slash = parseSlashDraft(text);
    if (text.length === 0) {
      return;
    }
    if (slash !== null) {
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

  private pickGallery(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    pickImageFromGallery(ctx).then((img: PickedImage | null): void => {
      if (img === null) {
        return;
      }
      this.imageError = img.error;
      if (img.error.length === 0) {
        if (this.pendingImages.length >= 6) {
          this.imageError = '一条消息最多带 6 张图片';
          return;
        }
        this.pendingImages = [...this.pendingImages, img];
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

  build() {
    Column() {
      if (this.lastError() !== null) {
        ErrorBanner({ message: this.lastError() as string })
      }
      if (this.permHint.length > 0) {
        HintBanner({ message: this.permHint, a11y: '权限提示，点按关闭', onDismiss: (): void => {
          this.permHint = '';
        } })
      }
      if (this.imageError.length > 0) {
        HintBanner({ message: this.imageError, danger: true, a11y: '图片错误提示，点按关闭', onDismiss: (): void => {
          this.imageError = '';
        } })
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
          sessions: this.atSessions,
          onPick: (e: AtEntry): void => this.applyAtEntry(e),
          onRetry: (): void => this.retryAt(),
          onPickSession: (h: AtSessionHit): void => this.applySession(h),
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
      if (this.pendingImages.length > 0) {
        ImageChips({
          names: this.pendingNames(),
          onRemove: (index: number): void => {
            const next: PickedImage[] = [];
            for (let i = 0; i < this.pendingImages.length; i++) {
              if (i !== index) {
                next.push(this.pendingImages[i]);
              }
            }
            this.pendingImages = next;
          }
        })
      }
      ComposerActions({
        hasPending: this.hasPending(),
        streaming: this.streaming(),
        sendEnabled: this.sendEnabled(),
        permissionLabel: this.permissionLabel(),
        wide: this.atLeastMd(),
        onPickImage: (): void => this.pickGallery(),
        onProject: (): void => this.openProjectPanel(),
        onPermission: (): void => {
          this.permSheetOpen = true;
        },
        onSend: (): void => this.send(),
        onStop: (): void => this.stop(),
      })
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
    .constraintSize({ maxWidth: this.columnWidth > 0 ? floatingColumnWidth(this.columnWidth) : '100%' })
    .bindSheet($$this.permSheetOpen, this.permissionContent(), {
      height: 320,
      showClose: false,
      backgroundColor: this.c().bgBase,
    })
  }

  private sendEnabled(): boolean {
    return (this.draft.trim() !== '' || this.hasPending()) && this.connected();
  }

  private permissionLabel(): string {
    return this.permView;
  }

  private lastError(): string | null {
    return this.errView.length === 0 ? null : this.errView;
  }
}
