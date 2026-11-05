/// 底部输入条：官方结构（ref/md-shot-2-lists.png 像素实测）——
/// 白色浮层容器（圆角 26dp + 阴影）：输入框；下一行权限档位 chip（真机反馈
/// 2026-11-04：原「深度思考」占位 chip 改为权限档位，对照桥 permission-options）
/// + 右侧「+」「语音」两个圆形按钮；容器下方居中免责提示。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/content.dart';
import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../bridge/permissions.dart';
import '../bridge/platform.dart';
import '../design/tokens.dart';

part 'composer_widgets.dart';

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

  /// 协议白名单（chat-adapter.ts:26-29；其它类型在选图时直接拒绝）。
  static const _imageWhitelist = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  DsColors get c => widget.colors;

  /// 权限 chip 的显示标签：有当前值显示其本地化标签，否则「权限」。
  String get _permissionLabel {
    final v = widget.currentPermission;
    if (v == null || v.isEmpty) return '权限';
    return permissionLabelOf(v);
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;
  bool get _hasImage => _pendingImage != null;

  // ---- 斜杠命令补全（真机反馈 2026-11-04 第 3 项）----

  /// 会话可用命令（进入命令草稿态时拉一次并缓存；切会话由 _commandsSid 失效）。
  List<SlashCommand>? _commands;
  String? _commandsSid;

  /// 当前命令草稿（`/` 开头才有）：（命令名片段, 已敲参数）。
  ({String nameFragment, String args})? get _slashDraft {
    if (!widget.enabled || widget.sessionId == null) return null;
    return parseSlashDraft(_controller.text);
  }

  /// 命令面板数据：草稿态 + 命令清单就绪时给出前缀过滤结果（最多 6 条）。
  List<SlashCommand> get _slashMatches {
    final draft = _slashDraft;
    final cmds = _commands;
    if (draft == null || cmds == null) return const [];
    final matches = cmds.where((c) => c.matchesQuery(draft.nameFragment));
    return matches.take(6).toList();
  }

  Future<void> _ensureCommands() async {
    final gw = widget.gateway;
    final sid = widget.sessionId;
    if (gw == null || sid == null) return;
    if (_commands != null && _commandsSid == sid) return;
    _commandsSid = sid;
    try {
      final raw = await gw.listCommands(sid);
      final list = SlashCommandList.from(raw);
      if (mounted) setState(() => _commands = list.commands);
    } on RequestException {
      // 命令清单拉不到就不给面板（发送路径仍可整行 execute，服务端会报错）。
      if (mounted) setState(() => _commands = const []);
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
  Future<void> _ensureAtEntries(String dir) async {
    final gw = widget.gateway;
    if (gw == null || _atLoading) return;
    if (_atLoadedDir == dir) return;
    _atLoading = true;
    try {
      if (_atRoots.isEmpty) {
        _atRoots = await gatewayListRoots(gw);
      }
      // 多根时先用第一个根（手机场景几乎都是单 workspace 根）。
      final root = _atRoots.isEmpty ? null : _atRoots.first;
      final entries = root == null
          ? const <GatewayEntry>[]
          : await gatewayListEntries(gw, root.id, dir.isEmpty ? '' : dir);
      if (mounted) {
        setState(() {
          _atMatches = entries;
          _atLoadedDir = dir;
        });
      }
    } on RequestException {
      if (mounted) setState(() => _atMatches = const []);
    } finally {
      _atLoading = false;
    }
  }

  /// 点选 @ 条目：目录→追加 `/` 继续下钻；文件→整段替换为 `@path `。
  void _applyAtEntry(GatewayEntry e) {
    final draft = _atDraft;
    if (draft == null) return;
    if (e.isDirectory) {
      final next = '${_atLoadedDir ?? ''}${e.name}/';
      _controller.text =
          '${_controller.text.substring(0, draft.start)}@$next';
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

  /// 发送键三态（对照 companion ComposerSendPolicy.resolve）：
  /// 有正文或待发图片=发送；运行中且两者皆无=停止；其余=占位（语音键位）。
  /// 真机反馈 2026-11-04 第 2 项：单发图片（无文本）也要亮发送键。
  /// 加图按钮已常驻（第二轮反馈 D），不再挤在 disabled 态里。
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
      // 图片上限 8MiB 原始字节（companion MAX_SOURCE_IMAGE_BYTES 口径；
      // base64 后 ~10.7MiB，REST 12MiB 请求体内）。超限拒绝并提示。
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

  /// 调系统选择器选图 → 复制进缓存 → base64 暂存。
  Future<void> _pickImage() async {
    final picked = await DshPlatform.pickImage();
    if (picked == null || !mounted) return;
    final ext = picked['name']!.split('.').last.toLowerCase();
    final mediaType = _imageWhitelist[ext];
    if (mediaType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅支持 PNG/JPEG/WebP/GIF 图片')),
      );
      return;
    }
    final bytes = await File(picked['path']!).readAsBytes();
    setState(() {
      _pendingImage = (
        path: picked['path']!,
        name: picked['name']!,
        mediaType: mediaType,
        base64: base64Encode(bytes),
      );
    });
  }

  /// 拉取权限档位清单并弹出选择菜单（真机反馈 2026-11-04 第 4 项）。
  /// 服务端是权威：options 里没有的档位不出现；失败给明确提示。
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
    final current = widget.currentPermission;
    final selected = await showModalBottomSheet<PermissionOption>(
      context: context,
      backgroundColor: c.bgLayer1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DsSpacing.settingsCardRadius),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
              child: Text(
                '会话权限档位',
                style: DsTypography.baseStrong.copyWith(
                  color: c.labelPrimary,
                ),
              ),
            ),
            for (final o in options)
              ListTile(
                leading: Icon(
                  o.value == current ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: o.value == current ? c.brand : c.labelTertiary,
                ),
                title: Text(
                  o.label,
                  style: DsTypography.base.copyWith(color: c.labelPrimary),
                ),
                subtitle: o.descriptionLabel == null
                    ? null
                    : Text(
                        o.descriptionLabel!,
                        style: DsTypography.small.copyWith(
                          color: c.labelTertiary,
                        ),
                      ),
                onTap: () => Navigator.pop(context, o),
              ),
            const SizedBox(height: DsSpacing.settingsCardPadV),
          ],
        ),
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
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: c.settingsSurface,
          title: const Text('切换到完全权限？'),
          content: const Text('该档位不受沙箱限制，代理可以直接执行任何操作。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认切换'),
            ),
          ],
        ),
      );
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
          Container(
            decoration: BoxDecoration(
              color: c.inputFill,
              borderRadius: BorderRadius.circular(DsSpacing.composerRadius),
              boxShadow: [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(
              DsSpacing.composerPadH,
              DsSpacing.composerPadTop,
              DsSpacing.composerPadH,
              0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DsSpacing.composerTextInset,
                  ),
                  // 键盘上下/回车驱动候选面板（外接键盘 / 物理键盘）。
                  child: Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 5,
                      style: DsTypography.base.copyWith(color: c.labelPrimary),
                      cursorColor: c.brand,
                      decoration: InputDecoration(
                        hintText: widget.enabled ? '发消息或按住说话' : '未连接到 bridge',
                        hintStyle: DsTypography.inputPlaceholder.copyWith(
                          color: c.inputHintText,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) {
                        setState(() {});
                        // 进入 `/` 草稿态时按需拉命令清单（每会话一次）。
                        if (_slashDraft != null) _ensureCommands();
                        // 进入 `@` 草稿态时按需拉目录页（@ 面板数据）。
                        final at = _atDraft;
                        if (at != null) {
                          _ensureAtEntries(_atLoadedDir ?? '');
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Chip(
                      icon: Icons.verified_user_outlined,
                      label: _permissionLabel,
                      active: (widget.currentPermission ?? '').isNotEmpty,
                      colors: c,
                      onTap: _pickPermission,
                    ),
                    const Spacer(),
                    if (_pendingImage != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          avatar: Icon(
                            Icons.image_outlined,
                            size: DsSpacing.chipIconSize,
                            color: c.chipSelectedFg,
                          ),
                          label: Text(
                            _pendingImage!.name,
                            style: DsTypography.caption.copyWith(
                              color: c.chipSelectedFg,
                            ),
                          ),
                          onDeleted: () =>
                              setState(() => _pendingImage = null),
                          backgroundColor: c.chipSelectedBg,
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    // 加图按钮常驻（真机反馈 2026-11-04 第二轮 D）：
                    // 之前只在 disabled 态渲染，先打字就找不到加图入口。
                    // stop（执行中）不可加图；其余态都可。
                    if (_sendKeyState != _SendKeyState.stop) ...[
                      _RoundIconButton(
                        colors: c,
                        filled: false,
                        icon: Icons.add,
                        onPressed: widget.enabled ? _pickImage : null,
                      ),
                      const SizedBox(width: DsSpacing.composerButtonGap),
                    ],
                    switch (_sendKeyState) {
                      _SendKeyState.send || _SendKeyState.disabled =>
                        _RoundIconButton(
                          colors: c,
                          filled: _sendKeyState == _SendKeyState.send,
                          icon: _sendKeyState == _SendKeyState.send
                              ? Icons.arrow_upward
                              : Icons.graphic_eq,
                          onPressed: widget.enabled && _hasText ||
                                  (_hasImage && widget.enabled)
                              ? _send
                              : null,
                        ),
                      _SendKeyState.stop => _RoundIconButton(
                          colors: c,
                          filled: true,
                          icon: Icons.stop,
                          onPressed: widget.enabled ? widget.onCancel : null,
                        ),
                    },
                  ],
                ),
              ],
            ),
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
