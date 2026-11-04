/// 底部输入条：官方结构（ref/md-shot-2-lists.png 像素实测）——
/// 白色浮层容器（圆角 26dp + 阴影）：输入框；下一行权限档位 chip（真机反馈
/// 2026-11-04：原「深度思考」占位 chip 改为权限档位，对照桥 permission-options）
/// + 右侧「+」「语音」两个圆形按钮；容器下方居中免责提示。
library;

import 'package:flutter/material.dart';

import '../bridge/gateway.dart';
import '../bridge/permissions.dart';
import '../design/tokens.dart';

/// 发送键三态（对照 companion 的 ComposerSendPolicy）。
enum _SendKeyState { send, stop, disabled }

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.colors,
    required this.onSend,
    required this.onCancel,
    this.enabled = true,
    this.streaming = false,
    this.sessionId,
    this.gateway,
    this.currentPermission,
  });

  final DsColors colors;
  final ValueChanged<String> onSend;
  /// 运行中且输入为空时，发送键变成「停止」并回调这里（session-cancel）。
  final VoidCallback onCancel;
  final bool enabled;
  /// 是否有回合在跑（对照 companion 的 ComposerSendPolicy 三态）。
  final bool streaming;
  /// 权限档位 chip 需要：当前会话 id 与网关（拉 permission-options / 切档位）。
  final String? sessionId;
  final GatewayClient? gateway;
  /// 当前档位 value（来自会话投影 values.permissions.currentValue；可空）。
  final String? currentPermission;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  bool _loadingOptions = false;

  DsColors get c => widget.colors;

  /// 权限 chip 的显示标签：有当前值显示其本地化标签，否则「权限」。
  String get _permissionLabel {
    final v = widget.currentPermission;
    if (v == null || v.isEmpty) return '权限';
    return permissionLabelOf(v);
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;

  /// 发送键三态（对照 companion ComposerSendPolicy.resolve）：
  /// 有正文=发送；运行中且无正文=停止；其余=占位（+ / 语音）。
  _SendKeyState get _sendKeyState {
    if (_hasText) return _SendKeyState.send;
    if (widget.streaming) return _SendKeyState.stop;
    return _SendKeyState.disabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    setState(() => _controller.clear());
  }

  /// 拉取权限档位清单并弹出选择菜单（真机反馈 2026-11-04 第 4 项）。
  /// 服务端是权威：options 里没有的档位不出现；失败给明确提示。
  Future<void> _pickPermission() async {
    final gw = widget.gateway;
    if (gw == null || _loadingOptions) return;
    setState(() => _loadingOptions = true);
    List<PermissionOption> options;
    try {
      final raw = await gw.permissionOptionsRaw();
      options = parsePermissionCatalog(raw).switchable;
    } on RequestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('权限档位获取失败：${e.message}')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
    if (!mounted || options.isEmpty) return;
    final current = widget.currentPermission;
    final selected = await showModalBottomSheet<PermissionOption>(
      context: context,
      backgroundColor: c.bgLayer1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DsSpacing.settingsCardRadius),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
              child: Text(
                '会话权限档位',
                style: DsTypography.baseStrong.copyWith(
                  color: c.labelPrimary,
                ),
              ),
            ),
            for (final o in options)
              ListTile(
                leading: Icon(
                  o.value == current ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: o.value == current ? c.brand : c.labelTertiary,
                ),
                title: Text(
                  o.label,
                  style: DsTypography.base.copyWith(color: c.labelPrimary),
                ),
                subtitle: o.descriptionLabel == null
                    ? null
                    : Text(
                        o.descriptionLabel!,
                        style: DsTypography.small.copyWith(
                          color: c.labelTertiary,
                        ),
                      ),
                onTap: () => Navigator.pop(context, o),
              ),
            const SizedBox(height: DsSpacing.settingsCardPadV),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final sid = widget.sessionId;
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先打开一个会话再切换权限档位')),
      );
      return;
    }
    if (selected.needsConfirm) {
      final ok = await showDialog<bool>(
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
      if (ok != true || !mounted) return;
    }
    try {
      await widget.gateway!.setPermission(sid, selected.value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('权限已切换为「${selected.label}」')),
        );
      }
    } on RequestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换失败：${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.composerMargin,
        DsSpacing.blockGap,
        DsSpacing.composerMargin,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
                  child: TextField(
                    controller: _controller,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: 5,
                    style: DsTypography.base.copyWith(color: c.labelPrimary),
                    cursorColor: c.brand,
                    decoration: InputDecoration(
                      hintText: widget.enabled ? '发消息或按住说话' : '未连接到 bridge',
                      hintStyle: DsTypography.inputPlaceholder.copyWith(
                        color: c.inputHintText,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Chip(
                      icon: Icons.verified_user_outlined,
                      label: _permissionLabel,
                      active: (widget.currentPermission ?? '').isNotEmpty,
                      colors: c,
                      onTap: _pickPermission,
                    ),
                    const Spacer(),
                    switch (_sendKeyState) {
                      _SendKeyState.send => _RoundIconButton(
                          colors: c,
                          filled: true,
                          icon: Icons.arrow_upward,
                          onPressed: widget.enabled ? _send : null,
                        ),
                      _SendKeyState.stop => _RoundIconButton(
                          colors: c,
                          filled: true,
                          icon: Icons.stop,
                          onPressed: widget.enabled ? widget.onCancel : null,
                        ),
                      _SendKeyState.disabled => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RoundIconButton(
                              colors: c,
                              filled: false,
                              icon: Icons.add,
                              onPressed: null,
                            ),
                            const SizedBox(width: DsSpacing.composerButtonGap),
                            _RoundIconButton(
                              colors: c,
                              filled: false,
                              icon: Icons.graphic_eq,
                              onPressed: null,
                            ),
                          ],
                        ),
                    },
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: DsSpacing.composerHintGap),
          Text(
            '回答由 AI 生成，仅供参考',
            style: DsTypography.caption.copyWith(color: c.inputHintText),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// 胶囊 chip：未选中为白底 + 细描边，选中为浅蓝底 + 品牌色文字。
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.active,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? colors.chipSelectedFg : colors.labelPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
      child: Container(
        height: DsSpacing.chipHeight,
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.chipPadH),
        decoration: BoxDecoration(
          color: active ? colors.chipSelectedBg : colors.inputFill,
          borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
          border: Border.all(
            color: active ? colors.chipSelectedBg : colors.inputBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: DsSpacing.chipIconSize, color: fg),
            const SizedBox(width: DsSpacing.chipIconGap),
            Text(label, style: DsTypography.chipLabel.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 圆形按钮：filled=品牌色实心（发送），否则细描边（+ / 语音）。
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.colors,
    required this.filled,
    required this.icon,
    required this.onPressed,
  });

  final DsColors colors;
  final bool filled;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DsSpacing.composerButtonSize,
      height: DsSpacing.composerButtonSize,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18),
        color: filled ? colors.onBrand : colors.labelPrimary,
        style: IconButton.styleFrom(
          backgroundColor: filled ? colors.brand : colors.none,
          shape: CircleBorder(
            side: filled
                ? BorderSide.none
                : BorderSide(color: colors.labelPrimary, width: 1.4),
          ),
        ),
      ),
    );
  }
}
