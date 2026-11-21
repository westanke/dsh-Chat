// 斜杠命令面板（从 composer_panels.dart 拆出，宪法 §7 单文件 ≤500 行）。
// 同为 composer.dart 的 part。
//
// 三态逐条对齐 dsh-go `slash_palette.dart`：
// 候选列表（名字打了一半）/ 参数提示（名字打完了等参数）/ 不显示。
// 视觉规格也照 dsh-go：容器圆角 28、最高 5.5 行、行左右内缩 6、行圆角 22、
// 行最小高 52、图标槽 32、尾部回车符 16（仅「回车就是它」那一行亮起）。
part of 'composer.dart';

/// 斜杠命令面板：[content] 只会是候选态或参数提示态（不显示态由调用方跳过）。
class _CommandPanel extends StatelessWidget {
  const _CommandPanel({
    super.key,
    required this.colors,
    required this.content,
    required this.onPick,
    this.highlighted = -1,
    this.onHighlightChanged,
  });

  final DsColors colors;
  final PaletteContent content;
  final ValueChanged<SlashCommand> onPick;
  final int highlighted;
  final ValueChanged<int>? onHighlightChanged;

  /// dsh-go `AppMotion.quick` 的近似值：高亮底色与回车符淡入。
  static const _fade = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    // 容器语义（dsh-go `Semantics(container, label: activitySlashCommands)`）：
    // 读屏把整块当「指令」区域，行内各自是按钮。
    return Semantics(
      container: true,
      label: '指令',
      child: Padding(
        padding: const EdgeInsets.only(bottom: DsSpacing.chipIconGap),
        child: Container(
          constraints: const BoxConstraints(
            maxHeight: DsSpacing.paletteMaxHeight,
          ),
          decoration: BoxDecoration(
            color: colors.inputFill,
            borderRadius: BorderRadius.circular(DsSpacing.paletteRadius),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: switch (content) {
            PaletteHint(:final command) => Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DsSpacing.paletteRowInset,
              ),
              child: _hintRow(command),
            ),
            PaletteMatches(
              :final matches,
              :final typed,
              :final hasSuffix,
              :final query,
            ) =>
              matches.isEmpty
                  ? _emptyRow(query)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        vertical: DsSpacing.paletteRowInset,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < matches.length; i++)
                            _matchRow(
                              matches[i],
                              index: i,
                              typed: typed,
                              hasSuffix: hasSuffix,
                            ),
                        ],
                      ),
                    ),
            PaletteNone() => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _matchRow(
    SlashCommand cmd, {
    required int index,
    required bool typed,
    required bool hasSuffix,
  }) {
    final selected = index == highlighted || (typed && index == 0);
    final intent = _intent(cmd, hasSuffix: hasSuffix);
    final detail = cmd.description.isEmpty
        ? intent
        : '$intent · ${cmd.description}';
    return _tile(
      cmd: cmd,
      detail: detail,
      selected: selected,
      // 只有「打了半个名字」时第一行代表回车，才挂回车符。
      showEnter: typed && index == 0,
      onTap: () => onPick(cmd),
      onHover: onHighlightChanged == null
          ? null
          : (h) {
              if (h) onHighlightChanged!(index);
            },
    );
  }

  /// 参数提示：名字已完整、命令要参数——单行说明「接着敲参数」，不可点。
  Widget _hintRow(SlashCommand cmd) => _tile(
    cmd: cmd,
    detail: cmd.description.isEmpty
        ? '输入参数后发送'
        : '${cmd.description} · 输入参数后发送',
    selected: false,
    showEnter: false,
    onTap: null,
    onHover: null,
  );

  /// 空态（dsh-go 单行：图标 + 一句「按普通消息发送」，不抄查询串）。
  Widget _emptyRow(String query) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.paletteEmptyPadLeft,
        DsSpacing.paletteEmptyPadTop,
        DsSpacing.paletteEmptyPadRight,
        DsSpacing.paletteEmptyPadTop,
      ),
      child: Row(
        children: [
          SizedBox(
            width: DsSpacing.paletteIconSlot,
            child: Icon(
              Icons.search_off,
              size: DsSpacing.paletteIconSize,
              color: colors.labelTertiary,
            ),
          ),
          const SizedBox(width: DsSpacing.paletteIconGap),
          Expanded(
            child: Text(
              '没有匹配的指令，按普通消息发送',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsTypography.caption.copyWith(color: colors.labelTertiary),
            ),
          ),
        ],
      ),
    );
  }

  /// 单行骨架：行缩进 6（高亮块比容器窄 6、圆角同心）+ 图标槽 32 + 两行文字
  /// + 可选尾部回车符。尺寸全部走 token（dsh-go slash_palette.dart 同值）。
  Widget _tile({
    required SlashCommand cmd,
    required String detail,
    required bool selected,
    required bool showEnter,
    required VoidCallback? onTap,
    required ValueChanged<bool>? onHover,
  }) {
    final radius = BorderRadius.circular(DsSpacing.paletteRowRadius);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.paletteRowInset,
      ),
      child: Semantics(
        button: onTap != null,
        label: '${cmd.displayLabel}，/${cmd.name}',
        hint: detail,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onHover: onHover,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: _fade,
              constraints: const BoxConstraints(
                minHeight: DsSpacing.paletteRowMinHeight,
              ),
              padding: const EdgeInsets.fromLTRB(
                DsSpacing.paletteRowPadLeft,
                DsSpacing.paletteRowPadV,
                DsSpacing.paletteRowPadRight,
                DsSpacing.paletteRowPadV,
              ),
              decoration: BoxDecoration(
                color: selected ? colors.paletteRowHighlight : colors.none,
                borderRadius: radius,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: DsSpacing.paletteIconSlot,
                    child: Icon(
                      _commandIcon(cmd),
                      size: DsSpacing.paletteIconSize,
                      color: colors.labelSecondary,
                    ),
                  ),
                  const SizedBox(width: DsSpacing.paletteIconGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _title(cmd),
                        if (detail.isNotEmpty)
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DsTypography.caption.copyWith(
                              color: colors.labelTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: showEnter ? 1 : 0,
                    duration: _fade,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: DsSpacing.paletteEnterGap,
                      ),
                      child: Icon(
                        Icons.keyboard_return,
                        size: DsSpacing.paletteEnterSize,
                        color: colors.labelTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `中文名  /name 参数占位` 三段（裸名保持等宽，用户看到的仍是可发送的 ASCII）。
  Widget _title(SlashCommand cmd) {
    final named = cmd.displayLabel != cmd.name;
    return Text.rich(
      TextSpan(
        children: [
          if (named)
            TextSpan(
              text: '${cmd.displayLabel}  ',
              style: DsTypography.baseStrong.copyWith(
                color: colors.labelPrimary,
              ),
            ),
          TextSpan(
            text: '/${cmd.name}',
            style: DsTypography.baseStrong.copyWith(
              color: named ? colors.labelSecondary : colors.labelPrimary,
              fontFamily: DsTypography.codeFamily,
            ),
          ),
          if (cmd.inputHint != null)
            TextSpan(
              text: ' ${cmd.inputHint}',
              style: DsTypography.caption.copyWith(color: colors.labelTertiary),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 这一行点下去是插入还是直接跑（与 bridge/slash_commands.dart 同一判据；
/// 光标后有文本时也插入，由 slashPickCompletion 在补全时再判一次）。
bool _insertsText(SlashCommand cmd, {bool hasSuffix = false}) =>
    slashPickInsertsText(cmd, hasSuffix: hasSuffix);

/// 第二行的意图前缀（dsh-go 文案：技能 · 填入 / 命令 · 填入 / 命令 · 执行）。
String _intent(SlashCommand cmd, {required bool hasSuffix}) {
  if (cmd.kind == SlashCommandKind.skill) return '技能 · 填入';
  return _insertsText(cmd, hasSuffix: hasSuffix) ? '命令 · 填入' : '命令 · 执行';
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
