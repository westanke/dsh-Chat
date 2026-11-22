/// 斜杠命令补全的取数 / 过滤 / 点选 / 发送解析（composer.dart 的 part）。
///
/// 单独成文件是为了守住「单文件 ≤500 行」的工程纪律；面板数据三层：
/// 客户端功能（bridge/slash_commands.dart 的 appSlashCommands）
/// + 宿主命令（`commands` 帧，中文化并隐藏 export）+ 会话技能（内核 `skills/list`，
/// 走 kernel-call；桥没放行或内核没装技能就自动没有技能行，不报错）。
part of 'composer.dart';

extension on ComposerState {
  // ---- 斜杠命令补全（真机反馈 2026-11-04 第 3 项）----
  // 状态字段（_palette / _paletteSid / _commandsLoading）留在 composer.dart 主类里
  // —— Dart 扩展不能声明实例字段。

  /// 当前面板该显示什么：三态（候选 / 参数提示 / 不显示）由
  /// bridge/slash_commands.dart 的 paletteContentOf 判定，与 dsh-go 同判据。
  PaletteContent get _paletteContent {
    final palette = _palette;
    // 新对话也放面板（只有客户端功能那四条）：命令要挂会话才能执行，
    // 但面板先能看见、先能选，回车由 _trySendCommand 建会话（IKX5MV）。
    if (!widget.enabled || palette == null) return const PaletteNone();
    // 用户主动关掉过（点外部/返回键/Esc），文本没变就别再弹。
    if (_dismissedSlashText != null) return const PaletteNone();
    return paletteContentOf(
      commands: palette,
      text: _controller.text,
      caret: _controller.selection.isValid
          ? _controller.selection.end
          : _controller.text.length,
    );
  }

  /// 关掉面板（点外部 / 返回键 / Esc），记下当前文本；与 dsh-go
  /// `_dismissSlashPalette` 同判据：已经关过或当前不是斜杠输入就什么都不做。
  void _dismissSlashPalette() {
    if (_dismissedSlashText != null) return;
    if (parseSlashInput(_controller.text) == null) return;
    _refresh(() => _dismissedSlashText = _controller.text);
  }

  /// 输入变化后复位关闭标记（dsh-go `_resetSlashDismissal`）：离开斜杠输入、
  /// 或重新敲成裸 `/` 就重新允许弹出。
  void _resetSlashDismissal() {
    if (_dismissedSlashText == null) return;
    _dismissedSlashText = resetSlashDismissal(
      _dismissedSlashText,
      _controller.text,
    );
  }

  /// 候选行（仅候选态非空；参数提示态与不显示态都是空表）。
  List<SlashCommand> get _slashMatches {
    final content = _paletteContent;
    return content is PaletteMatches ? content.matches : const [];
  }

  /// 拉一次面板清单并缓存：宿主命令走 `commands` 帧，技能走内核 `skills/list`
  /// （kernel-call；桥没放行/内核没装就自动没有技能行，不报错）。
  Future<void> _ensureCommands() async {
    final gw = widget.gateway;
    final sid = widget.sessionId;
    if (gw == null) return;
    if (_palette != null && _paletteSid == sid) return;
    if (sid == null) {
      // 新对话拉不到宿主命令（`commands` 帧要 sessionId），先只放客户端功能；
      // 会话建好后 didUpdateWidget 会按新 sid 重拉一次（IKX5MV）。
      _refresh(() {
        _palette = mergePaletteCommands(host: const []);
        _paletteSid = null;
      });
      return;
    }
    if (_commandsLoading) return;
    _commandsLoading = true;
    try {
      final host = paletteHostCommands(await _loadHostCommands(gw, sid));
      final skills = await _loadSkillCommands(gw, sid);
      if (mounted) {
        _refresh(() {
          _palette = mergePaletteCommands(host: host, skills: skills);
          _paletteSid = sid;
        });
      }
    } on RequestException {
      // 宿主命令都拉不到就只留客户端功能（发送路径仍可整行 execute，服务端会报错）。
      // 失败不落缓存（_paletteSid 不置），下次 onChanged 还会重试——m04149。
      if (mounted) {
        _refresh(() => _palette = mergePaletteCommands(host: const []));
      }
    } finally {
      _commandsLoading = false;
    }
  }

  Future<List<SlashCommand>> _loadHostCommands(
    GatewayClient gw,
    String sid,
  ) async {
    final raw = await gw.listCommands(sid);
    return SlashCommandList.from(raw).commands;
  }

  /// 会话技能（内核 `skills/list`）：失败一律当「没有技能」，不影响命令面板。
  Future<List<SlashCommand>> _loadSkillCommands(
    GatewayClient gw,
    String sid,
  ) async {
    if (!gw.kernelCallsEnabled ||
        gw.kernelEndpoint(kSkillsListEndpoint) == null) {
      return const [];
    }
    try {
      final res = await gw.kernelCall(
        kSkillsListEndpoint,
        args: {
          'request': {'sessionId': sid},
        },
      );
      return res.ok ? paletteSkillCommands(res.value) : const [];
    } on RequestException {
      return const [];
    }
  }

  /// 点选一行（面板点击 / 键盘回车选中 / 发送时自动选中第一行都走这里）。
  ///
  /// 与 dsh-go `_pick` 一致：能插入的插入（保留光标后的文本），不能插入的
  /// 直接执行——无参宿主命令点一下就跑，不必再让用户敲回车。
  void _applyCommand(SlashCommand cmd, {bool atCaret = true}) {
    final text = _controller.text;
    final caret = atCaret && _controller.selection.isValid
        ? _controller.selection.end
        : text.length;
    final completion = slashPickCompletion(
      _palette ?? const [],
      cmd,
      text,
      caret,
    );
    if (completion == null) {
      _runSlash(cmd, '/${cmd.name}');
      return;
    }
    _controller.value = TextEditingValue(
      text: completion.text,
      selection: TextSelection.collapsed(offset: completion.caret),
    );
    _focus.requestFocus();
    _refresh(() {});
  }

  /// 真正执行一条命令（已确定不插入输入框）。
  void _runSlash(SlashCommand cmd, String line) {
    switch (cmd.kind) {
      case SlashCommandKind.app:
        // 客户端功能：清掉草稿，本地执行，绝不发给桥（服务端会 404）。
        _controller.clear();
        _refresh(() {});
        widget.onAppCommand?.call(cmd.name);
      case SlashCommandKind.skill:
        // 技能行本该插入文本让用户补参数；走到这里说明调用方要求直接执行，
        // 与 dsh-go 的 `case skill: _pick(command)` 一样退回插入。
        _applyCommand(cmd);
      case SlashCommandKind.host:
        _controller.clear();
        _refresh(() {});
        widget.onCommand(line);
    }
  }

  /// 回车发送时的分流：普通消息 / 吃掉回车 / 执行整行 / 选中第一行。
  ///
  /// 返回 true 表示这次回车已被命令面板消费，调用方不要再当消息发出去。
  bool _trySendCommand() {
    if (_pendingImages.isNotEmpty) return false;
    final text = _controller.text;
    final draft = parseSlashInput(text);
    if (draft == null) return false;
    final sessionId = widget.sessionId;
    // 新对话没有 sessionId 也要走命令派发：命令卡先上屏，ChatState
    // ensureSessionOpen 建好会话后 execute（IKX5MV——老逻辑在这里直接
    // return false，`/tunnel` 被当正文发给了模型）。新对话面板里还没有
    // 宿主命令（`commands` 帧要 sessionId），用客户端功能兜底判定。
    final palette = _palette ??
        (sessionId == null ? appSlashCommands() : const <SlashCommand>[]);
    switch (classifySlashSend(palette, text)) {
      case SlashSendMessage():
        if (sessionId != null || draft.token.trim().isEmpty) return false;
        // 面板里没有、但形如 `/x`：仍按命令派发（服务端不认识会回错误卡，
        // 比静默降级成「发给模型」更诚实，也符合 issue 的验收）。
        _controller.clear();
        _refresh(() {});
        widget.onCommand(text.trim());
        return true;
      case SlashSendSwallow():
        // 只敲了一个 `/`：面板开着，等人挑一行。
        return true;
      case SlashSendRun(:final command, :final line):
        _runSlash(command, line);
        return true;
      case SlashSendPick(:final command):
        _applyCommand(command, atCaret: false);
        return true;
    }
  }
}
