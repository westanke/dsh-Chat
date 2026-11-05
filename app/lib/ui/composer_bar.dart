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
                o.value == current
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 20,
                color: o.value == current ? colors.brand : colors.labelTertiary,
              ),
              title: Text(
                o.label,
                style: DsTypography.base.copyWith(
                  color: colors.labelPrimary,
                ),
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
/// 加图与发送圆钮。纯展示 + 回调上行，状态都在 _ComposerState。
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
    required this.pendingImageName,
    required this.onRemoveImage,
    required this.showAddImage,
    required this.canPickImage,
    required this.onPickImage,
    required this.sendState,
    required this.canSend,
    required this.onSend,
    required this.onStop,
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

  /// 待发送图片名（null=无图片 chip）。
  final String? pendingImageName;
  final VoidCallback onRemoveImage;

  /// 加图按钮显隐（stop 态隐藏）与可用性（未连接禁用）。
  final bool showAddImage;
  final bool canPickImage;
  final VoidCallback? onPickImage;

  final _SendKeyState sendState;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      decoration: BoxDecoration(
        color: c.inputFill,
        borderRadius: BorderRadius.circular(DsSpacing.composerRadius),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.composerPadH,
        DsSpacing.composerPadTop,
        DsSpacing.composerPadH,
        0,
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
                style: DsTypography.base.copyWith(color: c.labelPrimary),
                cursorColor: c.brand,
                decoration: InputDecoration(
                  hintText: enabled ? '发消息或按住说话' : '未连接到 bridge',
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
              _Chip(
                icon: Icons.verified_user_outlined,
                label: permissionLabel,
                active: permissionActive,
                colors: c,
                onTap: onPickPermission,
              ),
              const Spacer(),
              if (pendingImageName != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    avatar: Icon(
                      Icons.image_outlined,
                      size: DsSpacing.chipIconSize,
                      color: c.chipSelectedFg,
                    ),
                    label: Text(
                      pendingImageName!,
                      style: DsTypography.caption.copyWith(
                        color: c.chipSelectedFg,
                      ),
                    ),
                    onDeleted: onRemoveImage,
                    backgroundColor: c.chipSelectedBg,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              // 加图按钮常驻（真机反馈 2026-11-04 第二轮 D）：
              // 之前只在 disabled 态渲染，先打字就找不到加图入口。
              // stop（执行中）不可加图；其余态都可。
              if (showAddImage) ...[
                _RoundIconButton(
                  colors: c,
                  filled: false,
                  icon: Icons.add,
                  onPressed: canPickImage ? onPickImage : null,
                ),
                const SizedBox(width: DsSpacing.composerButtonGap),
              ],
              switch (sendState) {
                _SendKeyState.send ||
                _SendKeyState.disabled =>
                  _RoundIconButton(
                    colors: c,
                    filled: sendState == _SendKeyState.send,
                    icon: sendState == _SendKeyState.send
                        ? Icons.arrow_upward
                        : Icons.graphic_eq,
                    onPressed: canSend ? onSend : null,
                  ),
                _SendKeyState.stop => _RoundIconButton(
                    colors: c,
                    filled: true,
                    icon: Icons.stop,
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
