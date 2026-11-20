/// 逐文件 diff 页：多文件横向切换 + 逐次修改的红绿差异块。
///
/// 对照 dsh-go（app/lib/ui/chat/diff_page.dart）。数据来自本轮工具调用的
/// arguments / meta.diffs（ui/turn_changes.dart），没有真实行号时显示
/// 「行号未知」——不猜。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import 'code_diff.dart';
import 'turn_changes.dart';

class ChatDiffPage extends StatefulWidget {
  const ChatDiffPage({
    super.key,
    required this.files,
    required this.colors,
    this.initialIndex = 0,
  });

  final List<FileChange> files;
  final DsColors colors;
  final int initialIndex;

  @override
  State<ChatDiffPage> createState() => _ChatDiffPageState();
}

class _ChatDiffPageState extends State<ChatDiffPage> {
  late int _index = widget.initialIndex.clamp(0, widget.files.length - 1);

  int get _added => widget.files.fold(0, (sum, f) => sum + f.added);
  int get _removed => widget.files.fold(0, (sum, f) => sum + f.removed);

  void _copyPath() {
    final file = widget.files[_index];
    Clipboard.setData(ClipboardData(text: file.path));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制路径'),
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final file = widget.files[_index];
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              count: widget.files.length,
              added: _added,
              removed: _removed,
              colors: colors,
              onBack: () => Navigator.of(context).maybePop(),
              onCopy: _copyPath,
            ),
            _FileTabs(
              files: widget.files,
              index: _index,
              colors: colors,
              onSelect: (i) => setState(() => _index = i),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    file.path,
                    style: DsTypography.codeBlockLabel.copyWith(
                      color: colors.labelSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '+${file.added}  −${file.removed}  '
                    '修改 ${file.edits} 次  行号未知',
                    style: DsTypography.small.copyWith(
                      color: colors.labelTertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final hunk in file.hunks) _HunkBlock(
                    hunk: hunk,
                    colors: colors,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.added,
    required this.removed,
    required this.colors,
    required this.onBack,
    required this.onCopy,
  });

  final int count;
  final int added;
  final int removed;
  final DsColors colors;
  final VoidCallback onBack;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(Icons.arrow_back, color: colors.labelPrimary),
            tooltip: '返回',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '本轮改动',
                  style: DsTypography.h4.copyWith(color: colors.labelPrimary),
                ),
                Text(
                  '$count 个文件  +$added −$removed',
                  style: DsTypography.small.copyWith(
                    color: colors.labelTertiary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: Icon(Icons.link, color: colors.labelSecondary),
            tooltip: '复制路径',
          ),
        ],
      ),
    );
  }
}

class _FileTabs extends StatelessWidget {
  const _FileTabs({
    required this.files,
    required this.index,
    required this.colors,
    required this.onSelect,
  });

  final List<FileChange> files;
  final int index;
  final DsColors colors;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == index;
          final file = files[i];
          return Center(
            child: InkWell(
              onTap: () => onSelect(i),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? colors.brand.withValues(alpha: 0.12) : null,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? colors.brand : colors.borderL2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      file.name,
                      style: DsTypography.small.copyWith(
                        color: selected ? colors.brand : colors.labelSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+${file.added}',
                      style: DsTypography.codeBlockLabel.copyWith(
                        color: colors.diffAdd,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '−${file.removed}',
                      style: DsTypography.codeBlockLabel.copyWith(
                        color: colors.diffRemove,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HunkBlock extends StatelessWidget {
  const _HunkBlock({required this.hunk, required this.colors});

  final EditHunk hunk;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第 ${hunk.index} 次修改',
            style: DsTypography.smallStrong.copyWith(
              color: colors.labelSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: colors.mdCodeBlockBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderL1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in hunk.lines) _DiffLineRow(line: line, colors: colors),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({required this.line, required this.colors});

  final CodeDiffLine line;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final (prefix, fg, bg) = switch (line.type) {
      CodeDiffLineType.add => ('+ ', colors.diffAdd, colors.diffAddBg),
      CodeDiffLineType.del => ('- ', colors.diffRemove, colors.diffRemoveBg),
      CodeDiffLineType.ctx => ('  ', colors.mdCodeBlockText, colors.mdCodeBlockBg),
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Text(
        '$prefix${line.text}',
        softWrap: true,
        style: DsTypography.codeBlock.copyWith(
          color: fg,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
