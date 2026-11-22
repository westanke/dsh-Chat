/// 空态的建议卡与技巧行（对齐 dsh-go `empty_actions.dart` / `empty_state.dart`）。
///
/// dsh-go 的空态在问候语下面有两样东西：
/// 1. **两列建议卡**（4 张）：每张一个彩色小方块图标 + 标题 + 一行说明，
///    点一下把 prompt 填进输入框（不直接发送，用户还能改）。
/// 2. **一条小技巧**：告诉用户一个真实存在的手势或入口，7 秒换一条。
///
/// 文案照 dsh-go 的 `app_zh.arb`（`viewSuggest*` / `viewTip*`）搬过来，
/// 只保留本仓**确实有**的能力——本仓没有「长按发送键插话」这类手势的，
/// 就不写进技巧池，宁缺不假。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// 一张建议卡：图标、标题、一行说明、点了填进输入框的 prompt。
///
/// [tint] 是图标的取色器（只用本仓 token，不引入官方色板）：
/// teal → brand、violet → chatStatusWarn 系、amber → warning、blue → info。
class EmptySuggestion {
  const EmptySuggestion({
    required this.icon,
    required this.label,
    required this.detail,
    required this.prompt,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String detail;
  final String prompt;
  final SuggestionTone tone;
}

/// 建议卡图标的色系（对应 dsh-go 的 teal / violet / amber / blue）。
enum SuggestionTone { brand, violet, amber, info }

/// 默认四张卡（文案取 dsh-go `viewSuggest*.label/detail/prompt`）。
const List<EmptySuggestion> kDefaultSuggestions = [
  EmptySuggestion(
    icon: Icons.folder_open,
    label: '看看工作区',
    detail: '列出文件和项目',
    prompt: '看看工作区里现在有哪些文件和项目，简单介绍一下。',
    tone: SuggestionTone.brand,
  ),
  EmptySuggestion(
    icon: Icons.code,
    label: '写个小脚本',
    detail: '统计词频并跑一次',
    prompt: '写一个 Python 脚本：统计一个文本文件里出现最多的 20 个词，并运行一次给我看结果。',
    tone: SuggestionTone.violet,
  ),
  EmptySuggestion(
    icon: Icons.terminal,
    label: '新建项目',
    detail: 'Node.js 带测试',
    prompt: '在工作区新建一个 Node.js 项目，配好 TypeScript 和一个最小的单元测试。',
    tone: SuggestionTone.amber,
  ),
  EmptySuggestion(
    icon: Icons.lightbulb_outline,
    label: '讲讲 Git',
    detail: 'rebase 和 merge',
    prompt: '用一个具体例子解释 git rebase 和 git merge 的区别，各自什么时候用。',
    tone: SuggestionTone.info,
  ),
];

/// 技巧池：每条都对应本仓**确实存在**的入口（用 `/` 面板、`+` 面板、
/// 抽屉筛选、活动条、上下文环、快捷键等），不写没实现的手势。
const List<String> kEmptyTips = [
  '输入 / 唤出指令：压缩上下文、切换模型、设目标等',
  '输入 @ 可以引用工作区里的文件或别的对话',
  '底部的活动条会告诉你这一轮正在做什么、跑了多久',
  '点输入条右侧的圆环，看上下文用了多少',
  '抽屉里能按「运行中」「待确认」筛会话',
  '「+」面板里的『权限』可以随时换沙箱档位',
  '长按助手回复可以复制、引用或重新生成',
  '顶部胶囊点一下，看这一轮的会话信息与统计',
];

/// 建议卡两列网格。
class SuggestionCards extends StatelessWidget {
  const SuggestionCards({
    super.key,
    required this.colors,
    required this.onPick,
    this.suggestions = kDefaultSuggestions,
  });

  final DsColors colors;
  final ValueChanged<String> onPick;
  final List<EmptySuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < suggestions.length; i += 2) {
      final left = suggestions[i];
      final right = i + 1 < suggestions.length ? suggestions[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            top: i == 0 ? 0 : DsSpacing.suggestionRowGap,
          ),
          child: Row(
            children: [
              Expanded(
                child: _SuggestionCard(
                  colors: colors,
                  suggestion: left,
                  onTap: () => onPick(left.prompt),
                ),
              ),
              const SizedBox(width: DsSpacing.suggestionRowGap),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _SuggestionCard(
                        colors: colors,
                        suggestion: right,
                        onTap: () => onPick(right.prompt),
                      ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.colors,
    required this.suggestion,
    required this.onTap,
  });

  final DsColors colors;
  final EmptySuggestion suggestion;
  final VoidCallback onTap;

  Color _tone() => switch (suggestion.tone) {
    SuggestionTone.brand => colors.brand,
    SuggestionTone.violet => colors.chatStatusWarn,
    SuggestionTone.amber => colors.chatStatusWarn,
    SuggestionTone.info => colors.labelSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // 描边一圈：浅色主题下 bgLayer1 与底色几乎同色，没有边就"飘"着。
    return Material(
      color: c.bgLayer1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DsSpacing.suggestionRadius),
        side: BorderSide(color: c.borderL1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DsSpacing.suggestionMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.all(DsSpacing.suggestionPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 彩色小方块图标（dsh-go badge 34 / glyph 18）。
                Container(
                  width: DsSpacing.suggestionBadge,
                  height: DsSpacing.suggestionBadge,
                  decoration: BoxDecoration(
                    color: _tone().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      DsSpacing.suggestionBadge * 0.32,
                    ),
                  ),
                  child: Icon(
                    suggestion.icon,
                    size: DsSpacing.suggestionGlyph,
                    color: _tone(),
                  ),
                ),
                const SizedBox(height: DsSpacing.suggestionTitleGap),
                Text(
                  suggestion.label,
                  style: DsTypography.smallStrong.copyWith(
                    color: c.labelPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  suggestion.detail,
                  style: DsTypography.caption.copyWith(color: c.labelTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一条小技巧，每 [interval] 换下一条（dsh-go 是 7 秒）。
class EmptyTip extends StatefulWidget {
  const EmptyTip({
    super.key,
    required this.colors,
    this.tips = kEmptyTips,
    this.interval = const Duration(seconds: 7),
  });

  final DsColors colors;
  final List<String> tips;
  final Duration interval;

  @override
  State<EmptyTip> createState() => _EmptyTipState();
}

class _EmptyTipState extends State<EmptyTip> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.tips.length > 1) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % widget.tips.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tips.isEmpty) return const SizedBox.shrink();
    final c = widget.colors;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: Text(
        '小技巧：${widget.tips[_index]}',
        key: ValueKey<int>(_index),
        style: DsTypography.caption.copyWith(color: c.labelTertiary),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
