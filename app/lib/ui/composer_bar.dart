// 输入容器与权限档位弹层（从 composer_widgets.dart 拆出，宪法 §7 单文件
// ≤500 行）。同为 composer.dart 的 part。
part of 'composer.dart';

/// 权限档位选择底部弹层（真机反馈 2026-11-04 第 4 项）。
/// 服务端是权威：options 里没有的档位不出现；当前档位打勾。
class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet({
    required this.colors,
    required this.options,
    required this.current,
  });

  final DsColors colors;
  final List<PermissionOption> options;

  /// 当前档位 value（可空=尚未设置，无一打勾）。
  final String? current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
            child: Text(
              '会话权限档位',
              style: DsTypography.baseStrong.copyWith(
                color: colors.labelPrimary,
              ),
            ),
          ),
          for (final o in options)
            ListTile(
              leading: Icon(
                o.value == current ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: o.value == current ? colors.brand : colors.labelTertiary,
              ),
              title: Text(
                o.label,
                style: DsTypography.base.copyWith(color: colors.labelPrimary),
              ),
              subtitle: o.descriptionLabel == null
                  ? null
                  : Text(
                      o.descriptionLabel!,
                      style: DsTypography.small.copyWith(
                        color: colors.labelTertiary,
                      ),
                    ),
              onTap: () => Navigator.pop(context, o),
            ),
          const SizedBox(height: DsSpacing.settingsCardPadV),
        ],
      ),
    );
  }
}

/// 输入容器（白浮层卡）：单行收起（没有输入）⇄ 双行展开（有文字/待发图）。
///
/// 几何交给 [_ComposerRows] 补间（对照 dsh-go `Composer`）：收起态是
/// `(+) 文字 … (环)(↑)` 的一行胶囊，展开后文字独占第一行，`+`、模型 chip、
/// 图片 chip、上下文环、发送键落到第二行。纯展示 + 回调上行，状态都在
/// ComposerState；开合只看内容（`controller.text` / `pendingImageNames`），
/// 不看焦点——用户要求「无输入默认收缩单行」。
class _ComposerBar extends StatefulWidget {
  const _ComposerBar({
    required this.colors,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onKey,
    required this.onChanged,
    required this.permissionLabel,
    required this.permissionActive,
    required this.onPickPermission,
    required this.pendingImageNames,
    required this.onRemoveImage,
    required this.canPickImage,
    required this.onPickImage,
    required this.onInsertContent,
    required this.sendState,
    required this.canSend,
    required this.onSend,
    required this.onStop,
    required this.answering,
    this.gateway,
    this.sessionId,
    this.modelLabel,
    this.onPickModel,
  });

  final DsColors colors;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final FocusOnKeyEventCallback onKey;
  final ValueChanged<String> onChanged;
  final String permissionLabel;
  final bool permissionActive;
  final VoidCallback onPickPermission;

  /// 待发送图片名（空=无图片 chip；多图按顺序横排）。
  final List<String> pendingImageNames;
  final ValueChanged<int> onRemoveImage;

  /// 加图/文件夹按钮的可用性（未连接时置灰）。按钮**常驻**，不再随发送键
  /// 三态隐藏——运行中空输入时也要能加图、能 @（2026-11-21 工单 5）。
  final bool canPickImage;
  final VoidCallback? onPickImage;
  final VoidCallback? onInsertContent;

  final _SendKeyState sendState;
  final bool canSend;

  /// 挂着单题提问：hint 说明这段文字会作为答案提交。
  final bool answering;
  final VoidCallback onSend;
  final VoidCallback? onStop;

  /// 输入条右侧的状态小件要自己按会话拉数据（上下文用量）。
  final GatewayClient? gateway;
  final String? sessionId;

  /// 模型 chip 显示的模型名（由 ChatState 持有；空 = 不显示 chip）。
  final String? modelLabel;

  /// 点模型 chip：上层打开模型选择（null = 不显示 chip）。
  final VoidCallback? onPickModel;

  @override
  State<_ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<_ComposerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: DsMotion.composerExpand,
  );

  late final Animation<double> _open = CurvedAnimation(
    parent: _expand,
    curve: DsMotion.composerExpandCurve,
  );

  /// 展开态：有文字或有待发图片。空输入一律单行收起。
  bool get _expanded =>
      widget.controller.text.trim().isNotEmpty ||
      widget.pendingImageNames.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncOpen);
    _expand.value = _expanded ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant _ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncOpen);
      widget.controller.addListener(_syncOpen);
    }
    _syncOpen();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncOpen);
    _expand.dispose();
    super.dispose();
  }

  /// 内容一变就把开合动画推向目标态；动画未结束时再次触发也只是改方向。
  void _syncOpen() {
    if (!mounted) return;
    if (_expanded) {
      _expand.forward();
    } else {
      _expand.reverse();
    }
  }

  /// 输入框可见行数上限：最多 6 行，且不超过键盘上方可用高度的 2/5
  /// （对照 dsh-go `Composer.linesFor`）。
  int _maxLines(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom;
    final line = media.textScaler.scale(DsSpacing.composerFontSize) *
        DsSpacing.composerLineHeight;
    if (line <= 0 || available <= 0) return 2;
    return (available * 0.4 / line).floor().clamp(2, 6);
  }

  /// 文字排到展开态整行宽度时的行数（只用来判断要不要「展开编辑」）。
  int _lineCount(BuildContext context) {
    final text = widget.controller.text;
    if (text.isEmpty) return 0;
    final width = MediaQuery.sizeOf(context).width -
        2 * DsSpacing.composerMargin -
        2 * DsSpacing.composerKeyGap -
        2 * DsSpacing.composerTextInset;
    if (width <= 0) return 0;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: DsSpacing.composerFontSize,
          height: DsSpacing.composerLineHeight,
        ),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: width);
    return painter.computeLineMetrics().length;
  }

  Widget _field(DsColors c, int maxLines) {
    return Focus(
      onKeyEvent: widget.onKey,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        minLines: 1,
        maxLines: maxLines,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        // dsh-go：字号 15、行高 1.45。
        style: DsTypography.base.copyWith(
          fontSize: DsSpacing.composerFontSize,
          height: DsSpacing.composerLineHeight,
          color: c.labelPrimary,
        ),
        cursorColor: c.brand,
        decoration: InputDecoration(
          // dsh-go 文案：空闲「给 DSH 发消息…」，生成中「生成中 · 可直接插话」。
          hintText: !widget.enabled
              ? '未连接到 bridge'
              : widget.answering
              ? '直接回答上面的提问…'
              : widget.onStop != null
              ? '生成中 · 可直接插话'
              : '给 DSH 发消息…',
          hintStyle: DsTypography.inputPlaceholder.copyWith(
            color: c.inputHintText,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }

  /// 展开后的第二行：模型 chip / 待发图片 / 「展开编辑」。
  ///
  /// 收起态由 [_ComposerRows] 整行隐藏；`Spacer` 保证没有左侧内容时右侧键
  /// 仍贴边。图片区用 `Expanded + 横向滚动`，多图/长文件名不会撑破输入条。
  Widget _footer(DsColors c, bool overflows) {
    return Row(
      children: [
        // 模型 chip：固定上限宽度，绝不参与 flex 分配——否则多图和窄屏时
        // 会挤走右侧按钮（工单 2 回归）。
        if (widget.onPickModel != null)
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DsSpacing.composerModelChipMaxWidth,
            ),
            child: ComposerModelChip(
              colors: c,
              modelLabel: widget.modelLabel,
              enabled: widget.enabled,
              onTap: widget.onPickModel!,
            ),
          ),
        // 待发送图片（真机反馈 2026-11-17 / 11-21 多图）：从左往右排，
        // 超出可横滑，单个 chip 单行省略。
        if (widget.pendingImageNames.isEmpty)
          const Spacer()
        else
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.pendingImageNames.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: DsSpacing.composerImageChipMaxWidth,
                          ),
                          child: Chip(
                            avatar: Icon(
                              Icons.image_outlined,
                              size: DsSpacing.chipIconSize,
                              color: c.chipSelectedFg,
                            ),
                            label: Text(
                              widget.pendingImageNames[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsTypography.caption.copyWith(
                                color: c.chipSelectedFg,
                              ),
                            ),
                            onDeleted: () => widget.onRemoveImage(i),
                            backgroundColor: c.chipSelectedBg,
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        // 输入超过可见行数：给一个明确出口，长文可以进全屏编辑。
        if (overflows)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Tooltip(
              message: '展开编辑',
              child: _RoundIconButton(
                colors: c,
                filled: false,
                quietFill: true,
                icon: Icons.open_in_full,
                iconSize: 18,
                onPressed: _openLongEditor,
              ),
            ),
          ),
      ],
    );
  }

  /// 收起态在左侧的「+」键。
  Widget _leading(DsColors c) {
    return _RoundIconButton(
      colors: c,
      filled: false,
      quietFill: true,
      icon: Icons.add,
      iconSize: 22,
      onPressed: widget.canPickImage ? widget.onPickImage : null,
    );
  }

  /// 上下文环 + 发送/停止键（两态都贴最右）。
  Widget _trailing(DsColors c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ComposerUsageRing(
          colors: c,
          gateway: widget.gateway,
          sessionId: widget.sessionId,
        ),
        const SizedBox(width: DsSpacing.composerButtonGap),
        switch (widget.sendState) {
          _SendKeyState.send ||
          _SendKeyState.disabled => _RoundIconButton(
            colors: c,
            filled: widget.sendState == _SendKeyState.send,
            quietFill: widget.sendState != _SendKeyState.send,
            icon: widget.sendState == _SendKeyState.send
                ? Icons.arrow_upward
                : Icons.graphic_eq,
            iconSize: widget.sendState == _SendKeyState.send ? 20 : 22,
            onPressed: widget.canSend ? widget.onSend : null,
          ),
          _SendKeyState.stop => _RoundIconButton(
            colors: c,
            filled: true,
            icon: Icons.stop,
            iconSize: 18,
            onPressed: widget.enabled ? widget.onStop : null,
          ),
        },
      ],
    );
  }

  /// 打开全屏长文编辑，回来把文字写回同一个 controller（继续走草稿保存）。
  Future<void> _openLongEditor() async {
    final text = await showComposerLongEditor(
      context,
      initial: widget.controller.text,
      colors: widget.colors,
    );
    if (!mounted || text == null) return;
    if (text != widget.controller.text) {
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      widget.onChanged(text);
    }
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final overflows = _lineCount(context) > _maxLines(context);
    return AnimatedBuilder(
      animation: _open,
      builder: (context, child) {
        final t = _open.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.inputFill,
            // dsh-go：单行 28（胶囊）/ 展开 20，开合时补间过去。
            borderRadius: BorderRadius.circular(
              ui.lerpDouble(
                DsSpacing.composerRadius,
                DsSpacing.composerRadiusOpen,
                t,
              )!,
            ),
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Padding(
        // dsh-go composer.dart:601-604：左 18（无 leading 时）/6，上右下各 6。
        padding: const EdgeInsets.all(DsSpacing.composerKeyGap),
        child: _ComposerRows(
          open: _open,
          children: [
            _field(c, _maxLines(context)),
            _leading(c),
            // 收起态整行隐藏；展开过半才淡入（Interval 与 dsh-go 一致）。
            FadeTransition(
              opacity: _open.drive(CurveTween(curve: const Interval(0.45, 1))),
              child: _footer(c, overflows),
            ),
            _trailing(c),
          ],
        ),
      ),
    );
  }
}

/// 「切换到完全权限」二次确认弹窗（权限档位 needsConfirm 时）。
Future<bool?> confirmFullPermission(BuildContext context, DsColors c) {
  return showDialog<bool>(
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
}
