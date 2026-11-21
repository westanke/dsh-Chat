/**
 * 输入条 —— 对照安卓 composer.dart/composer_bar.dart：斜杠命令补全 + @ 文件
 * 引用面板（含「选择项目中的内容」入口）+ 图片 chip + 权限档位 chip
 * （bindSheet 二次确认）+ 发送键三态 + 免责声明；面板壳在 ComposerPanels.ets。
 */
import { ChatStore } from '../core/ChatStore';
import { GatewayState } from '../core/GatewayEvents';
import { parseAtMentionDraft, AtMentionDraft, SlashCommand, SlashCommandKind } from '../core/Content';
import { PaletteContent, PaletteKind, PALETTE_NONE, parseSlashInput, resetSlashDismissalOn,
  paletteContentOf, slashPickCompletion,
  SlashCompletion, SlashSend, SlashSendKind, classifySlashSend, isAppCommand } from '../core/SlashCommands';
import { loadPaletteCommands } from '../core/SlashPalette';
import { GatewayRoot } from '../core/Files';
import { JsonMap } from '../core/JsonAccess';
import { PermissionSheet } from './PermissionSheet';
import { PickedImage, pickImageFromGallery, galleryErrorOf, promptPartsOf,
  imageNamesOf, withoutImageAt } from '../platform/PhotoPick';
import { CommandPanel, AtFilePanel } from './ComposerPanels';
import { ComposerShell } from './ComposerShell';
import { ComposerBanners } from './ComposerBanners';
import { AtEntry, AtSessionHit, AtMentionMerge, loadMergedAtEntries, inSubDirectory,
  insertFileMention,
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
  @State palette: SlashCommand[] = [];
  /** 命令面板三态内容（候选 / 参数提示 / 不显示）。 */
  @State paletteContent: PaletteContent = paletteContentOf([], '', 0);
  /** 面板被主动关掉时的输入快照（空串=没关过；dsh-go _dismissedSlashText）。 */
  @State dismissedSlash: string = '';
  /** 系统返回键先关面板：页面侧置 tick，这里收到就收起（dsh-go PopScope）。 */
  @StorageProp('dshSlashCloseTick') @Watch('onSlashCloseTick') slashCloseTick: number = 0;
  @State commandsSid: string = '';
  /** 客户端功能命令（/new /model /export /features）的执行回调，由 ChatView 接。 */
  onAppCommand: (name: string) => void = (): void => {};
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

  private connected(): boolean { return this.connectedView; }

  private streaming(): boolean { return this.streamingView; }

  private sid(): string {
    const st: ChatStore | null = this.store;
    return st === null ? '' : (st.sessionId ?? '');
  }

  private hasPending(): boolean { return this.pendingImages.length > 0; }

  private pendingNames(): string[] {
    return imageNamesOf(this.pendingImages);
  }

  /** ---------- 面板状态推导 ---------- */
  /** 光标真值回填：与 onChange 的「末尾估计」不同才重算面板
   *  （中途点击/方向键移动光标时，@ 片段解析依赖真实位置）。 */
  private onCaretMoved(start: number): void {
    if (start === this.cursor) {
      return;
    }
    this.cursor = start;
    this.updatePanel();
  }

  private onChanged(v: string): void {
    this.draft = v;
    // 光标兜底：onChange 先于 onTextSelectionChange 触发，刚敲下 '@' 那一帧
    // this.cursor 还停在上一次的位置（初值 0），parseAtMentionDraft('@', 0)
    // 永远返回 null —— 面板要等下一次输入才弹。输入必然把光标推到插入点之后，
    // 这里按「末尾」估一次先算面板；随后 onTextSelectionChange 拿真位置再校正。
    this.cursor = v.length;
    this.resetSlashDismissalHere();
    this.updatePanel();
  }

  private updatePanel(): void {
    // 命令清单按会话懒加载（切会话失效）；缺此调用会永远没有补全候选。
    this.ensureCommands();
    // 三态（候选 / 参数提示 / 不显示）与 dsh-go 同判据：名字打完带参数后
    // 面板收起，只在该命令要参数时留一行提示。
    const content: PaletteContent = this.dismissedSlash.length > 0
      ? PALETTE_NONE
      : paletteContentOf(this.palette, this.draft, this.cursor);
    this.paletteContent = content;
    if (content.kind !== PaletteKind.None) {
      this.panel = 'cmd';
      this.atDraft = null;
      AppStorage.setOrCreate('dshSlashPanelOpen', true);
      return;
    }
    const at = parseAtMentionDraft(this.draft, this.cursor);
    if (at !== null) {
      this.panel = 'at';
      this.atDraft = at;
      AppStorage.setOrCreate('dshSlashPanelOpen', false);
      const st: ChatStore | null = this.store;
      this.atSessions = sessionMatches(st === null ? [] : st.sessions,
        st === null ? null : st.sessionId, atLeafQuery(at.query));
      this.ensureAtEntries();
      return;
    }
    this.panel = 'none';
    this.atDraft = null;
    this.atSessions = [];
    AppStorage.setOrCreate('dshSlashPanelOpen', false);
  }

  onSlashCloseTick(): void {
    this.dismissSlash();
  }

  /** 关掉命令面板（返回键 / 点输入框外 / 失焦），记下当前文本。 */
  private dismissSlash(): void {
    if (this.dismissedSlash.length > 0 || parseSlashInput(this.draft) === null) {
      return;
    }
    this.dismissedSlash = this.draft;
    this.panel = 'none';
  }

  /** 输入变化后复位关闭标记（dsh-go _resetSlashDismissal）。 */
  private resetSlashDismissalHere(): void {
    if (this.dismissedSlash.length === 0) {
      return;
    }
    this.dismissedSlash = resetSlashDismissalOn(this.dismissedSlash, this.draft);
  }

  /** 命令面板清单（切会话失效；失败不落缓存，onChanged 自动重试）。
   *  三层来源与安卓 composer.dart 同口径：宿主 `commands` 帧 + 会话技能
   *  （内核 `skills/list`）+ 客户端四条功能命令；取数与合并下沉 core/SlashPalette.ts。 */
  private ensureCommands(): void {
    const st: ChatStore | null = this.store;
    const sid: string = this.sid();
    if (st === null || sid.length === 0 || this.commandsSid === sid) {
      return;
    }
    loadPaletteCommands(st.api, st.gateway, sid).then((list: SlashCommand[]): void => {
      this.palette = list;
      this.commandsSid = sid;
      this.updatePanel();
    }).catch((): void => {
      // 取数失败也要给客户端功能命令（离线可用的最小面板），且不落缓存。
      this.palette = [];
      this.updatePanel();
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

  /** 点选一行：能插入的插入（保留光标后的文本），不能插入的直接执行。 */
  private applyCommand(cmd: SlashCommand): void {
    const done: SlashCompletion | null = slashPickCompletion(this.palette, cmd,
      this.draft, this.cursor);
    if (done === null) {
      this.runSlash(cmd, '/' + cmd.name);
      return;
    }
    this.panel = 'none';
    this.draft = done.text;
    this.cursor = done.caret;
  }

  /** 真正执行一条命令（已确定不插入输入框）。 */
  private runSlash(cmd: SlashCommand, line: string): void {
    this.panel = 'none';
    if (isAppCommand(cmd)) {
      // 客户端功能命令：本地执行，绝不进输入框、绝不发服务端（服务端会 404）。
      this.draft = '';
      this.cursor = 0;
      this.onAppCommand(cmd.name);
      return;
    }
    if (cmd.kind === SlashCommandKind.Skill) {
      // 与 dsh-go 的 `case skill: _pick(command)` 一样退回插入。
      this.applyCommand(cmd);
      return;
    }
    const st: ChatStore | null = this.store;
    this.draft = '';
    this.cursor = 0;
    if (st !== null) {
      st.runCommand(line);
    }
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
    this.draft = insertFileMention(this.draft, at, e.name);
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
    if (images.length > 0) {
      this.draft = '';
      this.pendingImages = [];
      this.cursor = 0;
      this.panel = 'none';
      st.send(text, promptPartsOf(images), busyMode);
      return;
    }
    if (text.length === 0) {
      return;
    }
    // 回车分流与 dsh-go `_slashFor` 同口径：普通消息 / 吃掉回车 / 执行整行 /
    // 选中候选第一行。中文名（/目标）在执行前换成内核认的裸名（/goal）。
    const route: SlashSend = classifySlashSend(this.palette, text);
    if (route.kind === SlashSendKind.Swallow) {
      // 只敲了一个 `/`：面板开着，等人挑一行，这次回车不发消息。
      return;
    }
    if (route.kind === SlashSendKind.Run && route.command !== null) {
      this.runSlash(route.command, route.line);
      return;
    }
    if (route.kind === SlashSendKind.Pick && route.command !== null) {
      this.applyCommand(route.command);
      return;
    }
    this.draft = '';
    this.cursor = 0;
    this.panel = 'none';
    st.send(text, undefined, busyMode);
  }

  private stop(): void {
    const st: ChatStore | null = this.store;
    if (st !== null) { st.cancelTurn(); }
  }

  private pickGallery(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    pickImageFromGallery(ctx).then((img: PickedImage | null): void => {
      if (img === null) {
        return;
      }
      const err: string = galleryErrorOf(img, this.pendingImages.length);
      this.imageError = err;
      if (err.length === 0) {
        this.pendingImages = [...this.pendingImages, img];
      }
    }).catch((): void => {
      this.imageError = '图片读取失败';
    });
  }

  @Builder
  permissionContent() {
    PermissionSheet({ store: this.store, onDone: (m: string): void => { this.permHint = m; } })
  }

  build() {
    Column() {
      ComposerBanners({
        error: this.lastError() ?? '',
        permHint: this.permHint,
        imageError: this.imageError,
        onDismissPerm: (): void => {
          this.permHint = '';
        },
        onDismissImage: (): void => {
          this.imageError = '';
        },
      })
      if (this.panel === 'cmd') {
        CommandPanel({
          content: this.paletteContent,
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
      ComposerShell({
        text: this.draft,
        inputEnabled: this.connected(),
        imageNames: this.pendingNames(),
        hasPending: this.hasPending(),
        streaming: this.streaming(),
        sendEnabled: this.sendEnabled(),
        permissionLabel: this.permissionLabel(),
        wide: this.atLeastMd(),
        onChanged: (v: string): void => this.onChanged(v),
        onCaret: (start: number): void => this.onCaretMoved(start),
        onBlurred: (): void => this.dismissSlash(),
        onRemoveImage: (index: number): void => {
          this.pendingImages = withoutImageAt(this.pendingImages, index);
        },
        onPickImage: (): void => this.pickGallery(),
        onProject: (): void => this.openProjectPanel(),
        onPermission: (): void => {
          this.permSheetOpen = true;
        },
        onSend: (): void => this.send(),
        onStop: (): void => this.stop(),
      })
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

  private permissionLabel(): string { return this.permView; }

  private lastError(): string | null { return this.errView.length === 0 ? null : this.errView; }
}
