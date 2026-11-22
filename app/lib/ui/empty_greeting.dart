/// 空态问候块（从 chat_page.dart 拆出，避免页面文件越过 AGENTS §7 的 500 行线）：
/// 品牌标 + 问候语 + 工作目录 chip + 建议卡 + 技巧行。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'brand_mark.dart';
import 'chat_state.dart';
import 'empty_suggestions.dart';
import 'session_location_sheet.dart';

class EmptyGreeting extends StatelessWidget {
  const EmptyGreeting({
    super.key,
    required this.colors,
    required this.state,
    required this.onPickSuggestion,
  });

  final DsColors colors;
  final ChatState state;

  /// 点了建议卡：把 prompt 填进输入框（不直接发）。
  final ValueChanged<String> onPickSuggestion;

  @override
  Widget build(BuildContext context) {
    final loc = state.pendingLocation;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DsBrandMark(
            color: colors.brandMark,
            bellyColor: colors.bgBase,
            width: DsSpacing.brandMarkWidth,
            height: DsSpacing.brandMarkHeight,
          ),
          const SizedBox(height: DsSpacing.brandMarkGap),
          Text(
            '嗨！今天想聊些什么？',
            style: DsTypography.greeting.copyWith(color: colors.labelPrimary),
          ),
          // 工作目录选择（2026-11-15 反馈）：新建会话默认「手机会话」，
          // 发首条消息前可在此换成授权根下的指定目录。选中后 label 显示
          // 在 chip 上；会话建好后随 sessionId 定死（本组件只在空态显示）。
          const SizedBox(height: DsSpacing.liGap),
          InkWell(
            onTap: () => showSessionLocationSheet(context, state, colors),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors.bgLayer1,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.inputBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    loc == null ? Icons.smartphone : Icons.folder,
                    size: 15,
                    color: colors.brand,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '工作目录：${loc == null ? '手机会话（默认）' : loc.label}',
                    style: DsTypography.small.copyWith(
                      color: colors.labelPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more,
                    size: 15,
                    color: colors.labelTertiary,
                  ),
                ],
              ),
            ),
          ),
          // 建议卡与技巧行（dsh-go empty_actions 移植）：左右留出页面边距，
          // 桌面宽度下再限宽，两列不会被拉长也不会贴边。
          const SizedBox(height: DsSpacing.suggestionsGap),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.screenPad,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DsSpacing.suggestionsMaxWidth,
              ),
              child: SuggestionCards(
                colors: colors,
                onPick: onPickSuggestion,
              ),
            ),
          ),
          const SizedBox(height: DsSpacing.emptyTipGap),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.screenPad,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DsSpacing.suggestionsMaxWidth,
              ),
              child: EmptyTip(colors: colors),
            ),
          ),
        ],
      ),
    );
  }
}
