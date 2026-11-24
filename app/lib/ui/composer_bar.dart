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

/// 输入容器（白浮层卡）：输入框（键盘事件外抛）+ 权限 chip / 图片 chip /
/// 加图与发送圆钮。纯展示 + 回调上行，状态都在 ComposerState。
class _ComposerBar extends StatelessWidget {
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

  /// 输入框里的文字是否已经折到第二行。
  ///
  /// dsh-go `composer.dart:651` 按 `open` 在 28 → 20 之间补间（单行圆润、
  /// 多行收窄）。本仓是常驻双行布局，没有单行↔双行的切换，所以改按
  /// 「文字是否多行」来驱动同一段补间：一行时 28，多行时收敛到 20。
  bool _multiline(BuildContext context) {
    final text = controller.text;
    if (text.isEmpty) return false;
    final width =
        MediaQuery.sizeOf(context).width -
        2 * DsSpacing.screenPad -
        2 * DsSpacing.composerKeyGap -
        2 * DsSpacing.composerTextInset;
    if (width <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: DsSpacing.composerFontSize,
          height: DsSpacing.composerLineHeight,
        ),
      ),
      maxLines: 5,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    return painter.computeLineMetrics().length > 1;
  }

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final radius = _multiline(context)
        ? DsSpacing.composerRadiusOpen
        : DsSpacing.composerRadius;
    return AnimatedContainer(
      // dsh-go AppMotion.quick = 160ms：圆角在两个档之间滑过去，不跳。
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: c.inputFill,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // dsh-go composer.dart:601-604：左 18（无 leading 时）/6，上右下各 6。
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.composerKeyGap,
        DsSpacing.composerKeyGap,
        DsSpacing.composerKeyGap,
        DsSpacing.composerKeyGap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.composerTextInset,
            ),
            // 键盘上下/回车驱动候选面板（外接键盘 / 物理键盘）。
            child: Focus(
              onKeyEvent: onKey,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                // dsh-go：字号 15、行高 1.45。
                style: DsTypography.base.copyWith(
                  fontSize: DsSpacing.composerFontSize,
                  height: DsSpacing.composerLineHeight,
                  color: c.labelPrimary,
                ),
                cursorColor: c.brand,
                decoration: InputDecoration(
                  // dsh-go 文案：空闲「给 DSH 发消息…」，生成中「生成中 · 可直接插话」。
                  hintText: !enabled
                      ? '未连接到 bridge'
                      : answering
                      ? '直接回答上面的提问…'
                      : onStop != null
                      ? '生成中 · 可直接插话'
                      : '给 DSH 发消息…',
                  hintStyle: DsTypography.inputPlaceholder.copyWith(
                    color: c.inputHintText,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // 权限档位 chip 2026-11-22 移出输入条（dsh-go 的输入条只有
              // `+` / 文本框 / 模型 chip / 环 / 发送；权限在「+」面板的
              // 『本对话』第一行，同一个 `_pickPermission` 入口）。
              // 模型 chip：固定上限宽度，绝不参与 Row 的 flex 分配——
              // 否则多图和窄屏时会挤走右侧按钮（工单 2 回归）。
              if (onPickModel != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DsSpacing.composerModelChipMaxWidth,
                  ),
                  child: ComposerModelChip(
                    colors: c,
                    modelLabel: modelLabel,
                    enabled: enabled,
                    onTap: onPickModel!,
                  ),
                ),
              // 待发送图片（真机反馈 2026-11-17 / 11-21 多图）：
              // 文件名过长时 Chip 无界变宽，会把 Spacer 吃掉、把右侧按钮挤出
              // Row。有图时用 Expanded + 横向滚动 + 单行省略号，多个 chip 从左
              // 往右排，超出可横滑，永远不撑破输入条。
              if (pendingImageNames.isEmpty)
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
                          for (var i = 0; i < pendingImageNames.length; i++)
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
                                    pendingImageNames[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: DsTypography.caption.copyWith(
                                      color: c.chipSelectedFg,
                                    ),
                                  ),
                                  onDeleted: () => onRemoveImage(i),
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
              // 加图 / @ 引用两个圆钮常驻：不可用时置灰而不是消失
              // （2026-11-21 工单 5：运行中空输入时整排按钮消失）。
              _RoundIconButton(
                colors: c,
                filled: false,
                quietFill: true,
                icon: Icons.add,
                iconSize: 22,
                onPressed: canPickImage ? onPickImage : null,
              ),
              // 「@ 引用」圆钮 2026-11-22 移除：dsh-go 输入条只有 `+`，@ 引用
              // 挂在「+」面板的『文件』格（plus_panel → insertAtMention）。
              ComposerUsageRing(
                colors: c,
                gateway: gateway,
                sessionId: sessionId,
              ),
              const SizedBox(width: DsSpacing.composerButtonGap),
              switch (sendState) {
                _SendKeyState.send ||
                _SendKeyState.disabled => _RoundIconButton(
                  colors: c,
                  filled: sendState == _SendKeyState.send,
                  quietFill: sendState != _SendKeyState.send,
                  icon: sendState == _SendKeyState.send
                      ? Icons.arrow_upward
                      : Icons.graphic_eq,
                  iconSize: sendState == _SendKeyState.send ? 20 : 22,
                  onPressed: canSend ? onSend : null,
                ),
                _SendKeyState.stop => _RoundIconButton(
                  colors: c,
                  filled: true,
                  icon: Icons.stop,
                  iconSize: 18,
                  onPressed: enabled ? onStop : null,
                ),
              },
            ],
          ),
        ],
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
