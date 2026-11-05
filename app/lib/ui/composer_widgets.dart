part of 'composer.dart';

/// Composer 的私有小组件（宪法 §7 单文件 ≤500 行：chip / 圆形按钮 /
/// 斜杠命令建议面板 / @ 文件引用面板从 composer.dart 拆出）。

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

/// 协议白名单（chat-adapter.ts:26-29；其它类型在选图时直接拒绝）。
const _composerImageWhitelist = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

/// 白名单校验后的选图结果 → 读字节 → base64 暂存。
/// [picked] 是 DshPlatform.pickImage() 的结果（白名单校验在调用方 _pickImage，
/// 那里有 context 可以弹「仅支持 PNG/JPEG/WebP/GIF」提示）。
Future<({String path, String name, String mediaType, String base64})?>
pickComposerImage(Map<String, String> picked) async {
  final ext = picked['name']!.split('.').last.toLowerCase();
  final mediaType = _composerImageWhitelist[ext];
  if (mediaType == null) return null;
  final bytes = await File(picked['path']!).readAsBytes();
  return (
    path: picked['path']!,
    name: picked['name']!,
    mediaType: mediaType,
    base64: base64Encode(bytes),
  );
}
