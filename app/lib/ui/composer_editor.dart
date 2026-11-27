// 输入条的长文编辑弹层（part of composer.dart）。
part of 'composer.dart';

/// 长文编辑弹层：输入超过输入框可见行数时，从输入条第二行的「展开编辑」
/// 进来，把同一段文字放到整屏高度里改，点「完成」返回新文本。
///
/// 返回 `null` 表示取消（没点完成就退出），调用方保持原文字不动。
Future<String?> showComposerLongEditor(
  BuildContext context, {
  required String initial,
  required DsColors colors,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // 长文编辑时误拖下滑会丢掉未完成的编辑，这里只认「完成」与返回键。
    enableDrag: false,
    backgroundColor: colors.settingsSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DsSpacing.composerRadiusOpen),
      ),
    ),
    builder: (_) => _LongEditorSheet(initial: initial, colors: colors),
  );
}

class _LongEditorSheet extends StatefulWidget {
  const _LongEditorSheet({required this.initial, required this.colors});

  final String initial;
  final DsColors colors;

  @override
  State<_LongEditorSheet> createState() => _LongEditorSheetState();
}

class _LongEditorSheetState extends State<_LongEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final media = MediaQuery.of(context);
    final insets = media.viewInsets;
    // 键盘弹出后也要留得下输入区：高度按「键盘上方可用高度」算。
    final height = (media.size.height - insets.bottom) * 0.9;
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Text(
                    '编辑消息',
                    style: DsTypography.baseStrong.copyWith(
                      color: c.labelPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_controller.text.runes.length} 字',
                    style: DsTypography.caption.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
                  TextButton(onPressed: _done, child: const Text('完成')),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: c.borderL1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  style: DsTypography.base.copyWith(
                    fontSize: DsSpacing.composerFontSize,
                    height: DsSpacing.composerLineHeight,
                    color: c.labelPrimary,
                  ),
                  cursorColor: c.brand,
                  decoration: InputDecoration(
                    hintText: '编辑消息…',
                    hintStyle: DsTypography.inputPlaceholder.copyWith(
                      color: c.inputHintText,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
