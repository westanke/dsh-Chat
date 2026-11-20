/// 本轮改动卡：「改动了 N 个文件」+ 逐文件增删行数 + 「查看改动」。
///
/// 对照 dsh-go（app/lib/ui/chat/widgets/change_card.dart）：最多列 3 行，
/// 底栏给「还有 N 个文件」；点任意一行或「查看改动」进逐文件 diff 页。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'chat_diff_page.dart';
import 'turn_changes.dart';

class ChangeCard extends StatelessWidget {
  const ChangeCard({
    super.key,
    required this.changes,
    required this.colors,
  });

  final TurnChanges changes;
  final DsColors colors;

  static const int _shownCount = 3;

  void _open(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatDiffPage(
          files: changes.files,
          initialIndex: index,
          colors: colors,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = changes.files;
    final visible = files.take(_shownCount).toList();
    final hidden = files.length - visible.length;
    return Container(
      decoration: BoxDecoration(
        color: colors.bgLayer1,
        borderRadius: BorderRadius.circular(DsSpacing.bubbleRadius),
        border: Border.all(color: colors.borderL2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 18,
                  color: colors.labelSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '改动了 ${files.length} 个文件',
                    style: DsTypography.smallStrong.copyWith(
                      color: colors.labelPrimary,
                    ),
                  ),
                ),
                if (files.length > 1) ...[
                  Text(
                    '+${changes.added}',
                    style: DsTypography.smallStrong.copyWith(
                      color: colors.diffAdd,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '−${changes.removed}',
                    style: DsTypography.smallStrong.copyWith(
                      color: colors.diffRemove,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (var i = 0; i < visible.length; i++)
            _FileRow(
              file: visible[i],
              colors: colors,
              onTap: () => _open(context, i),
            ),
          const SizedBox(height: 4),
          Container(height: 1, color: colors.borderL1),
          InkWell(
            onTap: () => _open(context, 0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  Text(
                    '查看改动',
                    style: DsTypography.smallStrong.copyWith(
                      color: colors.brand,
                    ),
                  ),
                  const Spacer(),
                  if (hidden > 0)
                    Text(
                      '还有 $hidden 个文件',
                      style: DsTypography.small.copyWith(
                        color: colors.labelTertiary,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: colors.labelTertiary,
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

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.colors,
    required this.onTap,
  });

  final FileChange file;
  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 16,
              color: colors.labelTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.small.copyWith(
                      color: colors.labelPrimary,
                    ),
                  ),
                  if (file.directory.isNotEmpty)
                    Text(
                      file.directory,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.codeBlockLabel.copyWith(
                        color: colors.labelTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '+${file.added}',
              style: DsTypography.small.copyWith(color: colors.diffAdd),
            ),
            const SizedBox(width: 6),
            Text(
              '−${file.removed}',
              style: DsTypography.small.copyWith(color: colors.diffRemove),
            ),
          ],
        ),
      ),
    );
  }
}
