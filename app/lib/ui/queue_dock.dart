/// 排队管理（bridge `mobile-queue-v1` / IKX2AE）：输入条上方一行「排队 N 条」，
/// 点开面板逐条撤回 / 改插话 / 改写。队列身份用 inboxId（同文本可排两条）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/queue.dart';
import '../design/tokens.dart';
import 'chat_queue_actions.dart';
import 'chat_state.dart';

/// 输入条上方的队列条：没有排队项时不占位（由调用方判空）。
class QueueDockBar extends StatelessWidget {
  const QueueDockBar({
    super.key,
    required this.entries,
    required this.colors,
    required this.onManage,
  });

  final List<QueueEntry> entries;
  final DsColors colors;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final first = entries.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.composerMargin,
        DsSpacing.blockGap,
        DsSpacing.composerMargin,
        0,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
          onTap: onManage,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            decoration: BoxDecoration(
              color: colors.bgLayer1,
              borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
              border: Border.all(color: colors.borderL2, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_send_outlined,
                  size: DsSpacing.chipIconSize,
                  color: colors.labelTertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  '排队',
                  style: DsTypography.smallStrong.copyWith(
                    color: colors.labelSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entries.length == 1
                        ? first.text.replaceAll('\n', ' ')
                        : '${entries.length} 条 · 等本轮结束',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.caption.copyWith(
                      color: colors.labelPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '管理',
                  style: DsTypography.caption.copyWith(color: colors.brand),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.more_horiz,
                  size: DsSpacing.chipIconSize,
                  color: colors.labelTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 打开队列面板：逐条撤回 / 改插话 / 改写（改写带图项不给入口）。
Future<void> runQueueActions(
  BuildContext context,
  ChatState state,
  DsColors colors,
) async {
  if (state.queue.isEmpty) return;
  final action = await showModalBottomSheet<({QueueEntry entry, String kind})>(
    context: context,
    backgroundColor: colors.bgLayer1,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '排队中的消息',
                    style: DsTypography.baseStrong.copyWith(
                      color: colors.labelPrimary,
                    ),
                  ),
                ),
                Text(
                  '${state.queue.length} 条',
                  style: DsTypography.small.copyWith(
                    color: colors.labelTertiary,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final entry in state.queue)
                  ListTile(
                    title: Text(
                      entry.text.isEmpty ? '[图片]' : entry.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.base.copyWith(
                        color: colors.labelPrimary,
                      ),
                    ),
                    subtitle: Text(
                      queueSlotLabel(entry),
                      style: DsTypography.small.copyWith(
                        color: colors.labelTertiary,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      color: colors.bgLayer1,
                      icon: Icon(
                        Icons.more_horiz,
                        size: DsSpacing.chipIconSize,
                        color: colors.labelTertiary,
                      ),
                      onSelected: (kind) => Navigator.pop(
                        sheetContext,
                        (entry: entry, kind: kind),
                      ),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(
                            '撤回',
                            style: DsTypography.base.copyWith(
                              color: colors.labelPrimary,
                            ),
                          ),
                        ),
                        if (!entry.isNextStep)
                          PopupMenuItem(
                            value: 'steer',
                            child: Text(
                              '改插话（下一步就发）',
                              style: DsTypography.base.copyWith(
                                color: colors.labelPrimary,
                              ),
                            ),
                          ),
                        if (entry.canEdit)
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(
                              '改写后重发',
                              style: DsTypography.base.copyWith(
                                color: colors.labelPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: DsSpacing.settingsCardPadV),
        ],
      ),
    ),
  );
  if (action == null) return;
  final entry = action.entry;
  switch (action.kind) {
    case 'remove':
      await removeQueued(state, entry.inboxId);
    case 'steer':
      await steerQueued(state, entry.inboxId);
    case 'edit':
      if (!context.mounted) return;
      final edited = await _editQueuedText(context, entry, colors);
      if (edited == null) return;
      await editQueued(state, entry.inboxId, edited);
  }
  final error = state.lastError;
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}

Future<String?> _editQueuedText(
  BuildContext context,
  QueueEntry entry,
  DsColors colors,
) async {
  final controller = TextEditingController(text: entry.text);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: colors.bgLayer1,
      title: Text(
        '改写排队消息',
        style: DsTypography.baseStrong.copyWith(color: colors.labelPrimary),
      ),
      content: TextField(
        controller: controller,
        minLines: 2,
        maxLines: 6,
        autofocus: true,
        style: DsTypography.base.copyWith(color: colors.labelPrimary),
        decoration: InputDecoration(
          hintText: '改完会替换掉这条排队消息',
          hintStyle: DsTypography.small.copyWith(color: colors.labelTertiary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(dialogContext, text);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
