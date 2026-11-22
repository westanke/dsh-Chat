part of 'composer.dart';

/// Composer 的私有小组件（宪法 §7 单文件 ≤500 行：chip / 圆形按钮 /
/// 斜杠命令建议面板 / @ 文件引用面板从 composer.dart 拆出）。

// 输入条的权限胶囊 chip 2026-11-22 移除（dsh-go 输入条只有 `+` / 文本框 /
// 模型 chip / 环 / 发送；权限档位在「+」面板『本对话』第一行），
// 这里的 _Chip 随之删除，避免 analyze 报 unused_element。

/// 圆形按钮：filled=品牌色实心（发送），否则细描边（+ / 语音）。
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.colors,
    required this.filled,
    required this.icon,
    required this.onPressed,
    this.iconSize = 20,
    this.quietFill = false,
  });

  final DsColors colors;

  /// 主色实心（发送 / 停止）。false 时是淡底圆键（dsh-go 的 `+`）。
  final bool filled;
  final IconData icon;
  final VoidCallback? onPressed;
  final double iconSize;

  /// 淡底圆键（`+`、禁用态）：onSurface 6% 圆底、无描边。
  final bool quietFill;

  @override
  Widget build(BuildContext context) {
    // dsh-go composer：键一律 36 圆、图标 20（send）/18（stop）/22（`+`）。
    final disabled = onPressed == null;
    return SizedBox(
      width: DsSpacing.composerKeySize,
      height: DsSpacing.composerKeySize,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: iconSize),
        color: filled
            ? colors.onBrand
            : disabled
            ? colors.labelTertiary
            : colors.labelPrimary,
        style: IconButton.styleFrom(
          backgroundColor: filled
              ? (disabled ? colors.chipSelectedBg : colors.brand)
              : quietFill
              ? colors.chipSelectedBg
              : colors.none,
          shape: CircleBorder(
            side: filled || quietFill
                ? BorderSide.none
                : BorderSide(color: colors.labelPrimary, width: 1.4),
          ),
        ),
      ),
    );
  }
}

/// 解析选图回传：失败原因优先，其次核对真实 mediaType。
/// 原生侧已按字节魔数定类型并把 HEIC 等转码；旧版通道没回 mediaType 时
/// 读缓存字节自己嗅探（华为 DISPLAY_NAME 常无扩展名，不能按文件名猜，
/// 见 docs/huawei-heic-upload-report.md §4.2）。
Future<({String? error, String? mediaType})> resolvePickedImage(
  Map<String, String> picked,
) async {
  final error = picked['error'];
  if (error != null && error.isNotEmpty) {
    return (error: error, mediaType: null);
  }
  var mediaType = picked['mediaType'] ?? '';
  if (mediaType.isEmpty) {
    try {
      final bytes = await File(picked['path']!).readAsBytes();
      mediaType = sniffImageMediaType(bytes) ?? '';
    } on Object {
      mediaType = '';
    }
  }
  if (!isSupportedImageMediaType(mediaType)) {
    return (
      error: '无法识别的图片格式，请换一张 PNG/JPEG 图片',
      mediaType: null,
    );
  }
  return (error: null, mediaType: mediaType);
}

/// 选图结果 → 读字节 → base64 暂存。
/// [picked] 是 DshPlatform.pickImage() 的结果；mediaType 由原生侧按字节魔数
/// 判定并回传（内核不收的格式已转码），这里直接透传，不再按文件名扩展名猜。
Future<({String path, String name, String mediaType, String base64})?>
pickComposerImage(Map<String, String> picked, String mediaType) async {
  final bytes = await File(picked['path']!).readAsBytes();
  return (
    path: picked['path']!,
    name: picked['name']!,
    mediaType: mediaType,
    base64: base64Encode(bytes),
  );
}
