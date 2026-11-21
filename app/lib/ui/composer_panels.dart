// 斜杠命令面板与 @ 文件引用面板（从 composer_widgets.dart 拆出，
// 宪法 §7 单文件 ≤500 行）。同为 composer.dart 的 part。
part of 'composer.dart';

/// 斜杠命令建议面板（真机反馈 2026-11-04 第 3 项；第六轮 m03878：
/// 超过面板高度时可上下滚动，键盘上下键移动高亮行，回车选中）。
class _CommandPanel extends StatelessWidget {
  const _CommandPanel({
    required this.colors,
    required this.matches,
    required this.onPick,
    this.highlighted = -1,
    this.onHighlightChanged,
  });

  final DsColors colors;
  final List<SlashCommand> matches;
  final ValueChanged<SlashCommand> onPick;
  final int highlighted;
  final ValueChanged<int>? onHighlightChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: DsSpacing.chipIconGap),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // 高度由 composer 的外层限高容器统一滚动，这里不再自带 320 上限。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < matches.length; i++)
            InkWell(
              onTap: () => onPick(matches[i]),
              onHover: onHighlightChanged == null
                  ? null
                  : (h) {
                      if (h) onHighlightChanged!(i);
                    },
              borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpacing.settingsCardPadH,
                  vertical: DsSpacing.settingsCardPadV + 2,
                ),
                decoration: BoxDecoration(
                  color: i == highlighted ? colors.chipSelectedBg : colors.none,
                  borderRadius: BorderRadius.circular(
                    DsSpacing.settingsCardRadius,
                  ),
                ),
                child: _commandRow(matches[i]),
              ),
            ),
        ],
      ),
    );
  }

  /// 一条命令行：图标 + 「中文名 /name 参数占位」+ 第二行描述。
  ///
  /// 中文名来自 bridge/slash_commands.dart（first-party 按 definitionId 映射，
  /// 客户端功能自带），与 dsh-go 的 slash_palette 同形——裸名保持等宽，用户
  /// 敲 `/` 时看到的仍是可发送的 ASCII 命令。
  Widget _commandRow(SlashCommand cmd) {
    final label = cmd.displayLabel;
    final named = label != cmd.name;
    return Row(
      children: [
        Icon(
          _commandIcon(cmd),
          size: DsSpacing.chipIconSize + 2,
          color: colors.chipSelectedFg,
        ),
        const SizedBox(width: DsSpacing.chipIconGap + 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    if (named)
                      TextSpan(
                        text: '$label  ',
                        style: DsTypography.baseStrong.copyWith(
                          color: colors.labelPrimary,
                        ),
                      ),
                    TextSpan(
                      text: '/${cmd.name}',
                      style: DsTypography.baseStrong.copyWith(
                        color: named
                            ? colors.labelSecondary
                            : colors.labelPrimary,
                        fontFamily: DsTypography.codeFamily,
                      ),
                    ),
                    if (cmd.inputHint != null)
                      TextSpan(
                        text: ' ${cmd.inputHint}',
                        style: DsTypography.caption.copyWith(
                          color: colors.labelTertiary,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (cmd.description.isNotEmpty)
                Text(
                  cmd.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsTypography.caption.copyWith(
                    color: colors.labelTertiary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 命令行图标：客户端功能与 first-party 各有图腾，其余（插件命令、技能）
/// 用通用终端/星标，避免满屏一样的方块。
IconData _commandIcon(SlashCommand cmd) {
  if (cmd.kind == SlashCommandKind.skill) return Icons.auto_awesome;
  switch (cmd.name) {
    case 'new':
      return Icons.chat_bubble_outline;
    case 'model':
      return Icons.tune;
    case 'export':
      return Icons.download;
    case 'features':
      return Icons.apps;
    case 'compact':
      return Icons.compress;
    case 'permission':
      return Icons.lock_outline;
    case 'plan':
      return Icons.checklist;
    case 'goal':
      return Icons.flag_outlined;
    case 'feedback':
      return Icons.feedback_outlined;
    default:
      return Icons.terminal;
  }
}

/// @ 文件引用面板（第六轮反馈 m03878）：输入 `@` 时浮层列出当前授权根的
/// 目录条目（多根合并），按查询片段过滤；目录可点继续下钻，文件点选回填
/// `@label/path `。同样支持滚动 + 高亮。失败态显示错误行 + 点按重试（m04149）。
class _AtFilePanel extends StatelessWidget {
  const _AtFilePanel({
    required this.colors,
    required this.entries,
    required this.query,
    required this.rootLabel,
    required this.loading,
    required this.onPick,
    this.failed = false,
    this.onRetry,
    this.highlighted = -1,
    this.onHighlightChanged,
  });

  final DsColors colors;
  final List<GatewayEntry> entries;
  final String query;
  final String rootLabel;
  final bool loading;

  /// 目录页拉取失败（m04149）：显示错误行 + 点按重试，而不是假装「没有匹配」。
  final bool failed;
  final VoidCallback? onRetry;
  final ValueChanged<GatewayEntry> onPick;
  final int highlighted;
  final ValueChanged<int>? onHighlightChanged;

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final visible = entries
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q))
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: DsSpacing.chipIconGap),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: visible.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
              child: InkWell(
                onTap: failed && !loading ? onRetry : null,
                borderRadius: BorderRadius.circular(
                  DsSpacing.settingsCardRadius,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        loading
                            ? '正在加载目录…'
                            : failed
                            ? '目录加载失败，点按重试'
                            : '没有匹配的文件或目录',
                        style: DsTypography.caption.copyWith(
                          color: failed && !loading
                              ? colors.danger
                              : colors.labelTertiary,
                        ),
                      ),
                    ),
                    if (failed && !loading)
                      Icon(
                        Icons.refresh,
                        size: 16,
                        color: colors.labelTertiary,
                      ),
                  ],
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DsSpacing.settingsCardPadH,
                    DsSpacing.settingsCardPadV,
                    DsSpacing.settingsCardPadH,
                    0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 13,
                        color: colors.labelTertiary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          rootLabel.isEmpty ? '/' : rootLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsTypography.caption.copyWith(
                            color: colors.labelTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < visible.length; i++)
                  InkWell(
                    onTap: () => onPick(visible[i]),
                    onHover: onHighlightChanged == null
                        ? null
                        : (h) {
                            if (h) onHighlightChanged!(i);
                          },
                    borderRadius: BorderRadius.circular(
                      DsSpacing.settingsCardRadius,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: DsSpacing.settingsCardPadH,
                        vertical: DsSpacing.settingsCardPadV,
                      ),
                      decoration: BoxDecoration(
                        color: i == highlighted
                            ? colors.chipSelectedBg
                            : colors.none,
                        borderRadius: BorderRadius.circular(
                          DsSpacing.settingsCardRadius,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            visible[i].isDirectory
                                ? Icons.folder
                                : Icons.insert_drive_file,
                            size: DsSpacing.chipIconSize,
                            color: visible[i].isDirectory
                                ? colors.chipSelectedFg
                                : colors.labelSecondary,
                          ),
                          const SizedBox(width: DsSpacing.chipIconGap + 4),
                          Expanded(
                            child: Text(
                              visible[i].isDirectory
                                  ? '${visible[i].name}/'
                                  : visible[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsTypography.base.copyWith(
                                color: colors.labelPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// 多根 @ 目录拉取合并（m04149）：此前只取第一个根，若它恰好是空目录
/// （如 default-workspace）面板就永远为空。逐根拉取；多根时条目名加
/// `label/` 前缀防撞，单根保持原名。
Future<List<GatewayEntry>> fetchAtEntries(
  GatewayClient gw,
  List<GatewayRoot> roots,
  String dir,
) async {
  var merged = const <GatewayEntry>[];
  for (final root in roots) {
    final entries = await gatewayListEntries(gw, root.id, dir);
    if (roots.length > 1) {
      merged = [
        ...merged,
        ...entries.map(
          (e) => GatewayEntry(
            name: '${root.label}/${e.name}',
            // path 保持根内相对路径：@ 面板按目录下钻时要用它拼
            // gatewayListEntries(root.id, dir)，mention 也直接用它（@path）。
            path: e.path,
            kind: e.kind,
          ),
        ),
      ];
    } else {
      merged = entries;
    }
  }
  return merged;
}

/// 「选择项目中的内容」圆钮（对照官方 App 输入条，2026-11-16 通用设置批次）：
/// 在光标处插入 `@` 唤起 @ 文件面板——与手敲 @ 走同一状态路径
/// （_atDraft 解析 + _onChanged 预拉目录候选），不另起文件浏览器。
void insertAtMention(
  TextEditingController controller,
  ValueChanged<String> onChanged,
) {
  final text = controller.text;
  final raw = controller.selection.baseOffset;
  final offset = (raw < 0 ? text.length : raw).clamp(0, text.length);
  controller.value = TextEditingValue(
    text: '${text.substring(0, offset)}@${text.substring(offset)}',
    selection: TextSelection.collapsed(offset: offset + 1),
  );
  onChanged(controller.text);
}

/// @ 面板的「对话」分组（2026-11-21 工单 3）：输入 `@` 时把历史会话列在
/// 文件之前，点一下插入内核会话引用 `@[标题](dsh-session:<id>)`。
///
/// 数据源是抽屉同一份 `ChatState.sessions`，不额外请求内核——桥的白名单里
/// 没有 `sessionReferenceResolver/candidates`，客户端自己拼 mention 即可。
/// 文件 mention 文本（对齐官方 `formatFileMention`）：无空白 `@path`，含空白
/// 或引号 `@"path"`，目录以 `/` 结尾。
String fileMentionText(String path, {required bool directory}) {
  final p = directory && !path.endsWith('/') ? '$path/' : path;
  return '@${RegExp(r'[\s"]').hasMatch(p) ? '"${p.replaceAll('"', r'\"')}"' : p}';
}

/// 会话 mention 文本（对齐内核 `renderSessionMention`）：
/// `@[标题](dsh-session:<id>)`；标题里的 `]` 换成全角，避免提前闭合。
String sessionMentionText(String title, String id) {
  final label = title.trim().isEmpty ? id : title.trim();
  return '@[${label.replaceAll(']', '］')}](dsh-session:$id)';
}

/// 把草稿里 [start,end) 这段换成文件 mention，返回新文本与光标位置。
/// 目录还会补 `@dir/` 让面板继续下钻；文件补一个空格方便接着打字。
({String text, int offset}) insertFileMention(
  String text,
  int start,
  int end,
  String path, {
  required bool directory,
}) {
  final mention = fileMentionText(path, directory: directory);
  final tail = directory ? '' : ' ';
  return (
    text: '${text.substring(0, start)}$mention$tail${text.substring(end)}',
    offset: start + mention.length + tail.length,
  );
}

/// 把草稿里 [start,end) 这段换成会话 mention（`@[标题](dsh-session:id)`）。
({String text, int offset}) insertSessionMention(
  String text,
  int start,
  int end,
  String title,
  String id,
) {
  final mention = sessionMentionText(title, id);
  return (
    text: '${text.substring(0, start)}$mention ${text.substring(end)}',
    offset: start + mention.length + 1,
  );
}

/// 查询命中的历史会话（@ 面板「对话」分组）：去掉当前会话、标题非空、
/// 按标题子串过滤，最多 [max] 条。
List<DshSession> sessionMatches(
  List<DshSession> sessions,
  String? currentId,
  String query, {
  int max = 6,
}) {
  final q = query.toLowerCase();
  final out = <DshSession>[];
  for (final s in sessions) {
    if (s.id == currentId) continue;
    final title = (s.title ?? '').trim();
    if (title.isEmpty) continue;
    if (q.isNotEmpty && !title.toLowerCase().contains(q)) continue;
    out.add(s);
    if (out.length >= max) break;
  }
  return out;
}

/// 候选面板的键盘导航（从 composer.dart 抽出守 §7 行数）：上下键移动高亮、
/// 回车选中；面板没开或没有候选时把事件交还输入框。
KeyEventResult panelKeyEvent(
  FocusNode node,
  KeyEvent event, {
  required int count,
  required bool panelOpen,
  required int highlight,
  required ValueChanged<int> onHighlight,
  required VoidCallback onActivate,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  if (!panelOpen || count == 0) return KeyEventResult.ignored;
  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
    onHighlight((highlight + 1).clamp(0, count - 1));
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
    onHighlight((highlight - 1).clamp(0, count - 1));
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter) {
    if (highlight < 0 || highlight >= count) return KeyEventResult.ignored;
    onActivate();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
