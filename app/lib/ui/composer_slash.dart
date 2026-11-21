/// 斜杠命令补全的取数 / 过滤 / 点选 / 发送解析（composer.dart 的 part）。
///
/// 单独成文件是为了守住「单文件 ≤500 行」的工程纪律；面板数据三层：
/// 客户端功能（bridge/slash_commands.dart 的 appSlashCommands）
/// + 宿主命令（`commands` 帧，中文化并隐藏 export）+ 会话技能（内核 `skills/list`，
/// 走 kernel-call；桥没放行或内核没装技能就自动没有技能行，不报错）。
part of 'composer.dart';

extension on _ComposerState {
  // ---- 斜杠命令补全（真机反馈 2026-11-04 第 3 项）----
  // 状态字段（_palette / _paletteSid / _commandsLoading）留在 composer.dart 主类里
  // —— Dart 扩展不能声明实例字段。

  /// 当前命令草稿（`/` 开头才有）：（命令名片段, 已敲参数）。
  ({String nameFragment, String args})? get _slashDraft {
    if (!widget.enabled || widget.sessionId == null) return null;
    return parseSlashDraft(_controller.text);
  }

  /// 命令面板数据：草稿态 + 清单就绪时给出过滤结果（全量，面板自己滚动）。
  List<SlashCommand> get _slashMatches {
    final draft = _slashDraft;
    final palette = _palette;
    if (draft == null || palette == null) return const [];
    // 过滤口径对齐 dsh-go：裸名前缀 → 中文名前缀 → 包含 → 子序列，
    // 同级保序、空片段回全量（v1.0.11 曾 take(6) 截断——m04949）。
    return filterPaletteCommands(palette, draft.nameFragment);
  }

  /// 拉一次面板清单并缓存：宿主命令走 `commands` 帧，技能走内核 `skills/list`
  /// （kernel-call；桥没放行/内核没装就自动没有技能行，不报错）。
  Future<void> _ensureCommands() async {
    final gw = widget.gateway;
    final sid = widget.sessionId;
    if (gw == null || sid == null) return;
    if (_palette != null && _paletteSid == sid) return;
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

  /// 点选命令：客户端功能直接交给上层执行；其余把输入框换成 `/name ` 让用户
  /// 接着敲参数（dsh-go 的 `slashPickInsertsText` 同理——带参数提示才插入不发送）。
  void _applyCommand(SlashCommand cmd) {
    if (cmd.kind == SlashCommandKind.app) {
      // 本地功能：清掉 `/new` 这类草稿，别把它留在输入框里等发送。
      _controller.clear();
      _refresh(() {});
      widget.onAppCommand?.call(cmd.name);
      return;
    }
    final draft = _slashDraft;
    final args = draft?.args ?? '';
    _controller.text = args.isEmpty ? '/${cmd.name} ' : '/${cmd.name} $args';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _refresh(() {});
  }

  /// 发送时若整行是 `/xxx ...`（且没挂图片）→ 走命令执行而非聊天发送。
  bool _trySendCommand() {
    final sid = widget.sessionId;
    if (sid == null || _pendingImages.isNotEmpty) return false;
    final text = _controller.text.trim();
    if (!text.startsWith('/')) return false;
    // 首个 token 按面板清单解析：中文名也能认（`/目标 xxx` → `/goal xxx`，
    // dsh-go 的 resolveSlashCommand 同口径）；桥的服务端正则只认 ASCII 裸名。
    final token = text.substring(1).split(RegExp(r'\s+')).first;
    if (token.isEmpty) return false;
    final rest = text.substring(1 + token.length).trim();
    final cmd = resolvePaletteCommand(_palette ?? const [], token);
    if (cmd?.kind == SlashCommandKind.app) {
      // 手打 `/new` 这类客户端功能：本地执行，绝不发给桥（会 404）。
      _controller.clear();
      _refresh(() {});
      widget.onAppCommand?.call(cmd!.name);
      return true;
    }
    final line = cmd == null
        ? text
        : '/${cmd.name}${rest.isEmpty ? '' : ' $rest'}';
    widget.onCommand(line);
    _refresh(_controller.clear);
    return true;
  }

}
