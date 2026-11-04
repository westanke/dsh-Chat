/// 助手消息底部操作条 —— 官方 App 实测复刻。
///
/// 官方（ref/md-shot-3-code.png，1080x2400 @3.0）：
///   图标垂直中心 y≈1915，图标 30px ≈ 10dp 视觉尺寸（线框风格，tertiary 灰）；
///   左起 4 个：复制 / 点赞 / 朗读 / 分享，间距约 20dp；
///   最右侧单独一个「重新生成」刷新图标（x≈1001，右对齐）。
/// 点踩图标按真机反馈（2026-11-04）移除。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/platform.dart';
import '../design/tokens.dart';

/// 助手消息操作条：复制 / 喜欢 / 朗读 / 分享 —— 右侧重新生成。
class DsMessageActions extends StatefulWidget {
  const DsMessageActions({
    super.key,
    required this.colors,
    required this.text,
    this.onRegenerate,
  });

  final DsColors colors;
  final String text;
  final VoidCallback? onRegenerate;

  @override
  State<DsMessageActions> createState() => _DsMessageActionsState();
}

class _DsMessageActionsState extends State<DsMessageActions> {
  bool _liked = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// 朗读：调系统 TTS（dsh/platform 通道，真机反馈 2026-11-04）。
  /// 平台未实现（iOS 暂缓）或 TTS 失败时明确提示，不留死交互。
  Future<void> _speak(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context); // 组合期取，避免 async gap
    final ok = await DshPlatform.speak(widget.text);
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '正在朗读' : '朗读暂不可用')),
    );
  }

  /// 分享：调系统分享面板（Android Intent.createChooser）。
  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await DshPlatform.share(widget.text);
    if (!messenger.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('分享暂不可用')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: [
          _ActionIcon(
            icon: _copied ? Icons.check : Icons.content_copy_outlined,
            color: c.labelTertiary,
            tooltip: _copied ? '已复制' : '复制',
            onTap: _copy,
          ),
          _ActionIcon(
            icon: _liked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
            color: _liked ? c.brand : c.labelTertiary,
            tooltip: '喜欢',
            onTap: () => setState(() => _liked = !_liked),
          ),
          _ActionIcon(
            icon: Icons.volume_up_outlined,
            color: c.labelTertiary,
            tooltip: '朗读',
            onTap: () => _speak(context),
          ),
          _ActionIcon(
            icon: Icons.share_outlined,
            color: c.labelTertiary,
            tooltip: '分享',
            onTap: () => _share(context),
          ),
          const Spacer(),
          _ActionIcon(
            icon: Icons.refresh,
            color: c.labelTertiary,
            tooltip: '重新生成',
            onTap: widget.onRegenerate,
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.only(right: DsSpacing.actionIconGap),
          child: Icon(icon, size: DsSpacing.actionIconSize, color: color),
        ),
      ),
    );
  }
}
