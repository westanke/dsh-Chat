/// 底部输入条：官方结构——白浮层容器：输入框 + 权限档位 chip +
/// 「+」「语音」圆钮；容器下方居中免责提示。
library;

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../bridge/gateway.dart';
import '../bridge/image_media_type.dart';
import '../bridge/models.dart';
import '../bridge/permissions.dart';
import '../bridge/platform.dart';
import '../bridge/slash_commands.dart';
import '../design/tokens.dart';
import 'composer_status.dart';
import 'plus_panel.dart';
import 'window_class.dart';

part 'composer_widgets.dart';
part 'composer_panels.dart';
part 'composer_palette.dart';
part 'composer_at_sessions.dart';
part 'composer_bar.dart';
part 'composer_permission.dart';
part 'composer_slash.dart';

/// 待发送图片：选图后暂存，随下一条消息一起发（2026-11-21 起支持多张）。
typedef _PendingImage = ({
  String path,
  String name,
  String mediaType,
  String base64,
});

/// 发送键三态（对照 companion 的 ComposerSendPolicy）。
enum _SendKeyState { send, stop, disabled }

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.colors,
    required this.onSend,
    required this.onSendWithImages,
    required this.onCancel,
    required this.onCommand,
    this.enabled = true,
    this.streaming = false,
    this.sessionId,
    this.gateway,
    this.currentPermission,
    this.sessions = const [],
    this.answering = false,
    this.onAppCommand,
    this.onPickModel,
    this.topGap = DsSpacing.blockGap,
  });

  /// 与上方组件（活动条 / 任务条）的间距；有 dock 时传小值，避免叠成一大块空白。
  final double topGap;

  final DsColors colors;
  final ValueChanged<String> onSend;

  /// 带图发送（2026-11-04 单图 / 2026-11-21 多图）：文本可空、图片 part 必带。
  final void Function(String text, List<PromptPart> images) onSendWithImages;

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

  /// 历史会话（@ 面板「对话」分组的数据源：抽屉同一份 List）。
  final List<DshSession> sessions;

  /// 挂着一条「单题」待答提问：输入条文字直接当它的答案（hint 随之切换）。
  final bool answering;

  /// 客户端自带命令（new/model/export/features）点选后的本地动作。
  /// 这些名字服务端不认识，走 [onCommand] 会被桥 404，所以单独回调。
  final ValueChanged<String>? onAppCommand;

  /// 点输入条上的模型 chip：上层打开模型选择（null = 不显示 chip）。
  final VoidCallback? onPickModel;

  @override
  State<Composer> createState() => ComposerState();
}

/// 公开是为了让 ChatPage 用 GlobalKey 在返回键时先关面板
/// （dsh-go PopScope：面板开着时返回只收面板，不退页面）。
/// 嵌套 PopScope 在真机上不生效，所以改由外层页面统一分发。
class ComposerState extends State<Composer> {
  /// 斜杠面板当前是否可见。
  bool get paletteOpen => _paletteContent is! PaletteNone;

  /// 关掉斜杠面板（返回键路径）。
  void dismissPalette() => _dismissSlashPalette();

  /// 把一段文字填进输入框并聚焦（空态建议卡点一下就走这条路）。
  ///
  /// 只填不发：dsh-go 的建议卡也是把 prompt 放进输入框，用户还能改。
  void fillDraft(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
    notifyUiChanged();
  }

  /// 输入内容变化后的刷新入口（供 fillDraft 这类外部写入触发重绘）。
  void notifyUiChanged() => _refresh(() {});

  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loadingOptions = false;

  bool _commandsLoading = false; // 命令清单拉取防抖（m04149）
  bool _atFailed = false; // @ 目录页拉取失败过（面板显示错误态+重试，m04149）

  /// 候选面板当前高亮行（键盘上下键移动；-1=无高亮）。
  int _panelHighlight = -1;

  /// 当前面板里可见的 @ 条目（按草稿 `/` 后的片段过滤）。
  List<GatewayEntry> get _visibleAtEntries {
    final q = _atLeafQuery.toLowerCase();
    return _atMatches
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q))
        .toList();
  }

  /// 面板条目总数（命令或 @ 文件，随面板类型切换重置高亮）。
  int get _panelCount => (_atDraft != null && _slashMatches.isEmpty)
      ? _visibleAtEntries.length
      : _slashMatches.length;

  /// 键盘事件：面板可见时上下键移动高亮、回车选中；否则交还输入框。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final at = _atDraft;
    // Esc 先关面板（dsh-go chat_screen.dart 同口径），再让位给默认行为。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _paletteContent is! PaletteNone) {
      _dismissSlashPalette();
      return KeyEventResult.handled;
    }
    return panelKeyEvent(
      node,
      event,
      count: _panelCount,
      panelOpen: _slashMatches.isNotEmpty || at != null,
      highlight: _panelHighlight,
      onHighlight: (i) => setState(() => _panelHighlight = i),
      onActivate: _activateHighlight,
    );
  }

  /// 回车选中当前高亮项（@ 条目或斜杠命令）。
  void _activateHighlight() {
    final at = _atDraft;
    if (at != null && _slashMatches.isEmpty) {
      final visible = _visibleAtEntries;
      if (_panelHighlight < visible.length) {
        _applyAtEntry(visible[_panelHighlight]);
      }
    } else if (_panelHighlight < _slashMatches.length) {
      _applyCommand(_slashMatches[_panelHighlight]);
    }
  }

  /// 待发送图片（选图后暂存，随下一条消息一起发）。
  final List<_PendingImage> _pendingImages = [];

  /// 供 part 文件的扩展刷新界面：setState 是 protected，扩展里不能直接调。
  void _refresh(VoidCallback fn) => setState(fn);

  /// 一条消息最多带几张图（companion 没有硬上限；这里给个界面可控的数）。
  static const _maxImages = 6;

  DsColors get c => widget.colors;

  /// 权限 chip 的显示标签：有当前值显示其本地化标签，否则「权限」。
  String get _permissionLabel {
    final v = widget.currentPermission;
    if (v == null || v.isEmpty) return '权限';
    return permissionLabelOf(v);
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;
  bool get _hasImage => _pendingImages.isNotEmpty;

  /// 输入框 onChanged（_ComposerBar 回调）：刷新面板 + 按需拉命令/目录
  ///（m04149：失败不落缓存，下次输入自动重试）。
  void _onChanged(String _) {
    setState(() {});
    _resetSlashDismissal();
    if (parseSlashInput(_controller.text) != null) _ensureCommands();
    final at = _atDraft;
    if (at != null) {
      _ensureAtEntries(_atQueryDir);
    }
  }

  // ---- 斜杠命令补全（真机反馈 2026-11-04 第 3 项）----
  // 取数/过滤/点选/发送解析都在 composer_slash.dart 的 _ComposerSlash 扩展里
  //（拆文件守住单文件 ≤500 行纪律）；这里只留它们要用的状态字段。

  /// 面板全量清单（客户端功能 + 宿主命令 + 会话技能，见 bridge/slash_commands.dart）。
  /// null = 还没拉过；切会话由 _paletteSid 失效重拉。
  List<SlashCommand>? _palette;
  String? _paletteSid;

  /// 面板被用户主动关掉（点面板外 / Esc / 返回键）时的输入快照：文本不变就
  /// 不再弹，与 dsh-go `_dismissedSlashText` 同口径（输入变化由
  /// `_resetSlashDismissal` 复位）。
  String? _dismissedSlashText;

  // ---- @ 文件补全（第六轮反馈 m03878）----

  /// 当前 @ 草稿（光标前有未完结的 `@片段` 才有）。
  ({String query, int start, int end})? get _atDraft {
    if (!widget.enabled) return null;
    return parseAtMentionDraft(
      _controller.text,
      _controller.selection.baseOffset,
    );
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

  /// @ 草稿里 `/` 之前的目录（根内相对路径，''=根）。输入 `@src/li` 时列 `src`
  /// 的内容并用 `li` 过滤——面板只拉当前这一层，不做全树扫描。
  String get _atQueryDir {
    final q = _atDraft?.query ?? '';
    final i = q.lastIndexOf('/');
    return i < 0 ? '' : q.substring(0, i);
  }

  /// @ 草稿里 `/` 之后的片段（面板过滤用的名字片段）。
  String get _atLeafQuery {
    final q = _atDraft?.query ?? '';
    final i = q.lastIndexOf('/');
    return i < 0 ? q : q.substring(i + 1);
  }

  /// 当前查询命中的历史会话（@ 面板「对话」分组）。
  List<DshSession> get _atSessionMatches {
    final id = widget.sessionId;
    final draft = _atDraft;
    if (id == null || draft == null) return const [];
    return sessionMatches(widget.sessions, id, draft.query);
  }

  /// 点选历史会话：插入内核会话引用 `@[标题](dsh-session:<id>)`。
  void _applySessionEntry(DshSession session) {
    final draft = _atDraft;
    if (draft == null) return;
    final r = insertSessionMention(
      _controller.text,
      draft.start,
      draft.end,
      session.title ?? session.id,
      session.id,
    );
    _setDraftText(r.text, r.offset);
  }

  /// 点选 @ 条目：目录→`@dir/` 并继续下钻；文件→`@path`（含空白加引号）。
  void _applyAtEntry(GatewayEntry e) {
    final draft = _atDraft;
    if (draft == null) return;
    final r = insertFileMention(
      _controller.text,
      draft.start,
      draft.end,
      e.path,
      directory: e.isDirectory,
    );
    _setDraftText(r.text, r.offset);
    if (e.isDirectory) {
      _atLoadedDir = null; // 触发按新目录重拉
      _ensureAtEntries(e.path);
    }
  }

  void _setDraftText(String text, int offset) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    setState(() {});
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
    if (text.isEmpty && _pendingImages.isEmpty) return;
    // 斜杠命令优先（真机反馈 2026-11-04 第 3 项）：`/xxx args` 不进聊天。
    if (_trySendCommand()) return;
    final imgs = List<_PendingImage>.of(_pendingImages);
    if (imgs.isEmpty) {
      widget.onSend(text);
    } else {
      // 每张图上限 8MiB 原始字节（companion MAX_SOURCE_IMAGE_BYTES 口径）。
      for (final img in imgs) {
        final bytes = File(img.path).lengthSync();
        if (bytes > 8 * 1024 * 1024) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${img.name} 超过 8MB，请换一张')));
          return;
        }
      }
      widget.onSendWithImages(text, [
        for (final img in imgs)
          PromptPart.image(img.mediaType, img.base64, name: img.name),
      ]);
    }
    setState(() {
      _controller.clear();
      _pendingImages.clear();
    });
  }

  /// 调系统选择器选图 → 核对真实 mediaType → base64 暂存。
  /// 真实类型由原生侧按字节魔数判定并回传（HEIC 等已转码），这里不再按文件名
  /// 扩展名猜类型（华为 DISPLAY_NAME 常无扩展名，见 huawei-heic-upload-report.md）。
  /// 解析逻辑在 composer_widgets.dart 的 resolvePickedImage（同库顶层函数）。
  @override
  Widget build(BuildContext context) {
    final at = _atDraft;
    final slashMatches = _slashMatches;
    // 斜杠面板三态：候选（列表）/ 参数提示（单行）/ 不显示。
    final slashContent = at == null ? _paletteContent : const PaletteNone();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DsSpacing.composerMargin,
        widget.topGap,
        DsSpacing.composerMargin,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 面板整体限高内滚（屏幕 42%）：会话分组 + 文件/命令面板叠起来会顶出屏幕。
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.42,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (at != null && slashMatches.isEmpty) ...[
                    if (_atSessionMatches.isNotEmpty)
                      _AtSessionPanel(
                        colors: c,
                        sessions: _atSessionMatches,
                        onPick: _applySessionEntry,
                      ),
                    _AtFilePanel(
                      colors: c,
                      entries: _atMatches,
                      query: _atLeafQuery,
                      rootLabel: _atRoots.isEmpty ? '' : _atRoots.first.label,
                      loading: _atLoading,
                      failed: _atFailed,
                      onRetry: () {
                        _atLoadedDir = null;
                        _ensureAtEntries('');
                      },
                      highlighted: _panelHighlight,
                      onPick: _applyAtEntry,
                      onHighlightChanged: (i) =>
                          setState(() => _panelHighlight = i),
                    ),
                  ] else if (slashContent is! PaletteNone)
                    // 点面板外关闭 + 返回键先关面板（dsh-go TextFieldTapRegion
                    // / PopScope 同口径），出现时淡入并轻微上浮。
                    TextFieldTapRegion(
                      onTapOutside: (_) => _dismissSlashPalette(),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.bottomCenter,
                        // 候选 ⇄ 参数提示切换时淡入并轻微上浮（dsh-go
                        // AnimatedSwitcher + ScaleTransition(0.96→1) 同观感）。
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          switchInCurve: Curves.easeOut,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: 0.96,
                                end: 1,
                              ).animate(anim),
                              alignment: Alignment.bottomCenter,
                              child: child,
                            ),
                          ),
                          child: _CommandPanel(
                            colors: c,
                            key: ValueKey<String>(
                              slashContent.runtimeType.toString(),
                            ),
                            content: slashContent,
                            highlighted: _panelHighlight,
                            onPick: _applyCommand,
                            onHighlightChanged: (i) =>
                                setState(() => _panelHighlight = i),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
            pendingImageNames: [for (final i in _pendingImages) i.name],
            onRemoveImage: (i) => setState(() => _pendingImages.removeAt(i)),
            canPickImage: widget.enabled,
            onPickImage: _openPlusPanel,
            onInsertContent: () {
              _focus.requestFocus();
              insertAtMention(_controller, _onChanged);
            },
            sendState: _sendKeyState,
            canSend: widget.enabled && (_hasText || _hasImage),
            onSend: _send,
            onStop: widget.onCancel,
            answering: widget.answering,
            gateway: widget.gateway,
            sessionId: widget.sessionId,
            onPickModel: widget.onPickModel,
          ),
          const SizedBox(height: DsSpacing.composerHintGap),
          // 免责声明：流式思考中不显示（思考块已在消息流里滚动展示）。
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
