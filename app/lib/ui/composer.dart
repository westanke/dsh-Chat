/// 底部输入条：官方结构——白浮层容器：输入框 + 权限档位 chip +
/// 「+」「语音」圆钮；容器下方居中免责提示。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/content.dart';
import '../bridge/gateway.dart';
import '../bridge/image_media_type.dart';
import '../bridge/models.dart';
import '../bridge/permissions.dart';
import '../bridge/platform.dart';
import '../design/tokens.dart';

part 'composer_widgets.dart';
part 'composer_panels.dart';
part 'composer_bar.dart';

/// 发送键三态（对照 companion 的 ComposerSendPolicy）。
enum _SendKeyState { send, stop, disabled }

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.colors,
    required this.onSend,
    required this.onSendWithImage,
    required this.onCancel,
    required this.onCommand,
    this.enabled = true,
    this.streaming = false,
    this.sessionId,
    this.gateway,
    this.currentPermission,
  });

  final DsColors colors;
  final ValueChanged<String> onSend;
  /// 带图发送（真机反馈 2026-11-04 第 2 项）：文本可空、图片 part 必带。
  final void Function(String text, PromptPart image) onSendWithImage;
  /// 运行中且输入为空时，发送键变成「停止」并回调这里（session-cancel）。
  final VoidCallback onCancel;
  /// 斜杠命令执行回调（整行 `/xxx args` 发送时走这里；chat_state.runCommand）。
  final ValueChanged<String> onCommand;
  final bool enabled;
  /// 是否有回合在跑（对照 companion 的 ComposerSendPolicy 三态）。
  final bool streaming;
  /// 权限档位 chip 需要：当前会话 id 与网关（拉 permission-options / 切档位）。
  final String? sessionId;
  final GatewayClient? gateway;
  /// 当前档位 value（来自会话投影 values.permissions.currentValue；可空）。
  final String? currentPermission;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loadingOptions = false;

  bool _commandsLoading = false; // 命令清单拉取防抖（m04149）
  bool _atFailed = false; // @ 目录页拉取失败过（面板显示错误态+重试，m04149）

  /// 候选面板当前高亮行（键盘上下键移动；-1=无高亮）。
  int _panelHighlight = -1;

  /// 面板条目总数（命令或 @ 文件，随面板类型切换重置高亮）。
  int get _panelCount {
    final at = _atDraft;
    if (at != null && _slashMatches.isEmpty) {
      final q = at.query.toLowerCase();
      final visible = _atMatches
          .where((e) => q.isEmpty || e.name.toLowerCase().contains(q))
          .toList();
      return visible.length;
    }
    return _slashMatches.length;
  }

  /// 键盘事件：面板可见时上下键移动高亮、回车选中；否则交还输入框。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final count = _panelCount;
    if (count == 0) return KeyEventResult.ignored;
    final at = _atDraft;
    final panelOpen = _slashMatches.isNotEmpty || at != null;
    if (!panelOpen) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _panelHighlight = (_panelHighlight + 1).clamp(0, count - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _panelHighlight = (_panelHighlight - 1).clamp(0, count - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_panelHighlight < 0 || _panelHighlight >= count) {
        return KeyEventResult.ignored;
      }
      if (at != null && _slashMatches.isEmpty) {
        final q = at.query.toLowerCase();
        final visible = _atMatches
            .where((e) => q.isEmpty || e.name.toLowerCase().contains(q))
            .toList();
        if (_panelHighlight < visible.length) {
          _applyAtEntry(visible[_panelHighlight]);
          return KeyEventResult.handled;
        }
      } else if (_panelHighlight < _slashMatches.length) {
        _applyCommand(_slashMatches[_panelHighlight]);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// 待发送图片（选图后暂存，随下一条消息一起发；真机反馈 2026-11-04 第 2 项）。
  ({String path, String name, String mediaType, String base64})? _pendingImage;

  DsColors get c => widget.colors;

  /// 权限 chip 的显示标签：有当前值显示其本地化标签，否则「权限」。
  String get _permissionLabel {
    final v = widget.currentPermission;
    if (v == null || v.isEmpty) return '权限';
    return permissionLabelOf(v);
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;
  bool get _hasImage => _pendingImage != null;

  /// 输入框 onChanged（_ComposerBar 回调）：刷新面板 + 按需拉命令/目录
  ///（m04149：失败不落缓存，下次输入自动重试）。
  void _onChanged(String _) {
    setState(() {});
    if (_slashDraft != null) _ensureCommands();
    final at = _atDraft;
    if (at != null) {
      _ensureAtEntries(_atLoadedDir ?? '');
    }
  }

  // ---- 斜杠命令补全（真机反馈 2026-11-04 第 3 项）----

  /// 会话可用命令（进入命令草稿态时拉一次并缓存；切会话由 _commandsSid 失效）。
  List<SlashCommand>? _commands;
  String? _commandsSid;

  /// 当前命令草稿（`/` 开头才有）：（命令名片段, 已敲参数）。
  ({String nameFragment, String args})? get _slashDraft {
    if (!widget.enabled || widget.sessionId == null) return null;
    return parseSlashDraft(_controller.text);
  }

  /// 命令面板数据：草稿态 + 命令清单就绪时给出前缀过滤结果（全量）。
  List<SlashCommand> get _slashMatches {
    final draft = _slashDraft;
    final cmds = _commands;
    if (draft == null || cmds == null) return const [];
    // 前缀过滤后全量返回（v1.0.11 曾 take(6) 截断：命令按字母序返回，
    // t/z 开头的命令在 `/` 空草稿时被截掉、`/t` 过滤后才出现——m04949）。
    // 面板本身可滚动（maxHeight 320），高亮计数随长度自适应。
    return cmds.where((c) => c.matchesQuery(draft.nameFragment)).toList();
  }

  Future<void> _ensureCommands() async {
    final gw = widget.gateway;
    final sid = widget.sessionId;
    if (gw == null || sid == null) return;
    if (_commands != null && _commandsSid == sid) return;
    if (_commandsLoading) return;
    _commandsLoading = true;
    try {
      final raw = await gw.listCommands(sid);
      final list = SlashCommandList.from(raw);
      if (mounted) setState(() => _commands = list.commands);
    } on RequestException {
      // 命令清单拉不到就不给面板（发送路径仍可整行 execute，服务端会报错）。
      // 失败不落缓存（_commandsSid 不置），下次 onChanged 还会重试——m04149。
      if (mounted) setState(() => _commands = const []);
    } finally {
      _commandsLoading = false;
    }
  }

  /// 点选命令：输入框替换为 `/name ` 并聚焦，让用户接着敲参数。
  void _applyCommand(SlashCommand cmd) {
    final draft = _slashDraft;
    final args = draft?.args ?? '';
    _controller.text = args.isEmpty
        ? '/${cmd.name} '
        : '/${cmd.name} $args';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() {});
  }

  // ---- @ 文件补全（第六轮反馈 m03878）----

  /// 当前 @ 草稿（光标前有未完结的 `@片段` 才有）。
  ({String query, int start, int end})? get _atDraft {
    if (!widget.enabled) return null;
    return parseAtMentionDraft(_controller.text, _controller.selection.baseOffset);
  }

  /// @ 面板条目：目录 + 文件混合列表（懒加载一次根列表，随后按目录翻页）。
  List<GatewayEntry> _atMatches = const [];
  List<GatewayRoot> _atRoots = const [];
  String? _atLoadedDir; // 已加载条目对应的 WirePath（''=根）
  bool _atLoading = false;

  /// 拉取 [dir]（WirePath，''=根）的目录页；query 过滤交给面板渲染侧。
  /// m04149 修复：失败不落缓存（_atLoadedDir 不置），下次 onChanged 自动重试；
  /// 失败置 _atFailed 供面板显示错误态；多根逐根拉取合并（此前只取第一个根，
  /// 若它恰好是空目录（如 default-workspace）面板就永远为空）。
  Future<void> _ensureAtEntries(String dir) async {
    final gw = widget.gateway;
    if (gw == null || _atLoading) return;
    if (_atLoadedDir == dir && !_atFailed) return;
    _atLoading = true;
    try {
      if (_atRoots.isEmpty) {
        _atRoots = await gatewayListRoots(gw);
      }
      final merged = await fetchAtEntries(gw, _atRoots, dir);
      if (mounted) {
        setState(() {
          _atMatches = merged;
          _atLoadedDir = dir;
          _atFailed = false;
        });
      }
    } on RequestException {
      if (mounted) {
        setState(() {
          _atMatches = const [];
          _atFailed = true;
        });
      }
    } finally {
      _atLoading = false;
    }
  }

  /// 点选 @ 条目：目录→追加 `/` 继续下钻；文件→整段替换为 `@label/path `。
  /// 多根合并时条目名带 `label/` 前缀（fetchAtEntries 注入），先剥掉再拼。
  void _applyAtEntry(GatewayEntry e) {
    final draft = _atDraft;
    if (draft == null) return;
    final relName = _atRoots.length > 1 && e.name.contains('/')
        ? e.name.substring(e.name.indexOf('/') + 1)
        : e.name;
    if (e.isDirectory) {
      _controller.text =
          '${_controller.text.substring(0, draft.start)}@${_atLoadedDir ?? ''}$relName/';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _atLoadedDir = null; // 触发重新拉取
      setState(() {});
      return;
    }
    // 文件：替换 @片段 为完整相对路径。多根时补根标签前缀便于辨认。
    final root = _atRoots.isEmpty ? null : _atRoots.first;
    final display = root == null || root.label.isEmpty
        ? e.path
        : '${root.label}/${e.path}';
    _controller.text =
        '${_controller.text.substring(0, draft.start)}@$display ${_controller.text.substring(draft.end)}';
    _controller.selection = TextSelection.collapsed(
      offset: draft.start + display.length + 2,
    );
    setState(() {});
  }

  /// 发送时若整行是 `/xxx ...`（且没挂图片）→ 走命令执行而非聊天发送。
  bool _trySendCommand() {
    final sid = widget.sessionId;
    if (sid == null || _pendingImage != null) return false;
    final text = _controller.text.trim();
    if (!text.startsWith('/')) return false;
    final draft = parseSlashDraft(text);
    if (draft == null) return false;
    widget.onCommand(text);
    setState(() {
      _controller.clear();
    });
    return true;
  }

  /// 发送键三态（对照 companion ComposerSendPolicy.resolve）。
  _SendKeyState get _sendKeyState {
    if (_hasText || _hasImage) return _SendKeyState.send;
    if (widget.streaming) return _SendKeyState.stop;
    return _SendKeyState.disabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImage == null) return;
    // 斜杠命令优先（真机反馈 2026-11-04 第 3 项）：`/xxx args` 不进聊天。
    if (_trySendCommand()) return;
    final img = _pendingImage;
    if (img == null) {
      widget.onSend(text);
    } else {
      // 图片上限 8MiB 原始字节（companion MAX_SOURCE_IMAGE_BYTES 口径）。
      final bytes = File(img.path).lengthSync();
      if (bytes > 8 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片超过 8MB，请选小一点的图')),
        );
        return;
      }
      widget.onSendWithImage(
        text,
        PromptPart.image(img.mediaType, img.base64, name: img.name),
      );
    }
    setState(() {
      _controller.clear();
      _pendingImage = null;
    });
  }

  /// 调系统选择器选图 → 核对真实 mediaType → base64 暂存。
  /// 真实类型由原生侧按字节魔数判定并回传（HEIC 等已转码），这里不再按文件名
  /// 扩展名猜类型（华为 DISPLAY_NAME 常无扩展名，见 huawei-heic-upload-report.md）。
  /// 解析逻辑在 composer_widgets.dart 的 resolvePickedImage（同库顶层函数）。
  Future<void> _pickImage() async {
    final picked = await DshPlatform.pickImage();
    if (picked == null || !mounted) return;
    final resolved = await resolvePickedImage(picked);
    if (!mounted) return;
    if (resolved.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resolved.error!)),
      );
      return;
    }
    final img = await pickComposerImage(picked, resolved.mediaType!);
    if (img == null || !mounted) return;
    setState(() => _pendingImage = img);
  }

  /// 拉取权限档位清单并弹出选择菜单（服务端是权威；失败给明确提示）。
  Future<void> _pickPermission() async {
    final gw = widget.gateway;
    if (gw == null || _loadingOptions) return;
    setState(() => _loadingOptions = true);
    List<PermissionOption> options;
    try {
      final raw = await gw.permissionOptionsRaw();
      options = parsePermissionCatalog(raw).switchable;
    } on RequestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('权限档位获取失败：${e.message}')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
    if (!mounted || options.isEmpty) return;
    final selected = await showModalBottomSheet<PermissionOption>(
      context: context,
      backgroundColor: c.bgLayer1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DsSpacing.settingsCardRadius),
        ),
      ),
      builder: (context) => _PermissionSheet(
        colors: c,
        options: options,
        current: widget.currentPermission,
      ),
    );
    if (selected == null || !mounted) return;
    final sid = widget.sessionId;
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先打开一个会话再切换权限档位')),
      );
      return;
    }
    if (selected.needsConfirm) {
      final ok = await confirmFullPermission(context, c);
      if (ok != true || !mounted) return;
    }
    try {
      await widget.gateway!.setPermission(sid, selected.value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('权限已切换为「${selected.label}」')),
        );
      }
    } on RequestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换失败：${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final at = _atDraft;
    final slashMatches = _slashMatches;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.composerMargin,
        DsSpacing.blockGap,
        DsSpacing.composerMargin,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (at != null && slashMatches.isEmpty)
            _AtFilePanel(
              colors: c,
              entries: _atMatches,
              query: at.query,
              rootLabel: _atRoots.isEmpty ? '' : _atRoots.first.label,
              loading: _atLoading,
              failed: _atFailed,
              onRetry: () {
                _atLoadedDir = null;
                _ensureAtEntries('');
              },
              highlighted: _panelHighlight,
              onPick: _applyAtEntry,
              onHighlightChanged: (i) => setState(() => _panelHighlight = i),
            )
          else if (slashMatches.isNotEmpty)
            _CommandPanel(
              colors: c,
              matches: slashMatches,
              highlighted: _panelHighlight,
              onPick: _applyCommand,
              onHighlightChanged: (i) => setState(() => _panelHighlight = i),
            ),
          _ComposerBar(
            colors: c,
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            onKey: _onKey,
            onChanged: _onChanged,
            permissionLabel: _permissionLabel,
            permissionActive: (widget.currentPermission ?? '').isNotEmpty,
            onPickPermission: _pickPermission,
            pendingImageName: _pendingImage?.name,
            onRemoveImage: () => setState(() => _pendingImage = null),
            showAddImage: _sendKeyState != _SendKeyState.stop,
            canPickImage: widget.enabled,
            onPickImage: _pickImage,
            sendState: _sendKeyState,
            canSend: widget.enabled && _hasText || (_hasImage && widget.enabled),
            onSend: _send,
            onStop: widget.onCancel,
          ),
          const SizedBox(height: DsSpacing.composerHintGap),
          // 免责声明（真机反馈第五轮）：流式思考进行中不显示——
          // 思考块已在消息流里滚动展示，底部小字会跟着抢注意力；
          // 无思考（空闲 / 普通回答中）时照常显示。
          if (!widget.streaming)
            Text(
              '回答由 AI 生成，仅供参考',
              style: DsTypography.caption.copyWith(color: c.inputHintText),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
