/// 本轮生成文件卡：「生成了 N 个文件」+ 缩略图 + 文件名 + 类型说明。
///
/// 对照 dsh-go（app/lib/ui/chat/widgets/artifact_card.dart）：最多列 4 行，
/// 超出的收进「全部 N 个文件」。缩略图只在图片且能取到字节时显示，取不到
/// 退回类型图标——不留一个永远空着的方块。
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/platform.dart';
import '../design/tokens.dart';
import 'turn_changes.dart';

class ArtifactCard extends StatefulWidget {
  const ArtifactCard({
    super.key,
    required this.files,
    required this.colors,
    this.gateway,
  });

  final List<ArtifactFile> files;
  final DsColors colors;
  final GatewayClient? gateway;

  @override
  State<ArtifactCard> createState() => _ArtifactCardState();
}

class _ArtifactCardState extends State<ArtifactCard> {
  static const int _shownCount = 4;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final files = widget.files;
    final visible = _expanded ? files : files.take(_shownCount).toList();
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 17, color: colors.labelSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '生成了 ${files.length} 个文件',
                    style: DsTypography.smallStrong.copyWith(
                      color: colors.labelPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final file in visible)
            _ArtifactRow(
              file: file,
              colors: colors,
              gateway: widget.gateway,
            ),
          if (hidden > 0)
            InkWell(
              onTap: () => setState(() => _expanded = true),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Text(
                      '全部 ${files.length} 个文件',
                      style: DsTypography.small.copyWith(color: colors.brand),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: colors.brand,
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _ArtifactRow extends StatelessWidget {
  const _ArtifactRow({
    required this.file,
    required this.colors,
    required this.gateway,
  });

  final ArtifactFile file;
  final DsColors colors;
  final GatewayClient? gateway;

  Future<void> _menu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制路径'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('分享'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: file.path));
        messenger.showSnackBar(const SnackBar(content: Text('已复制路径')));
      case 'share':
        final ok = await DshPlatform.share(file.path);
        if (!ok) {
          messenger.showSnackBar(const SnackBar(content: Text('分享暂不可用')));
        }
      default:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _menu(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        child: Row(
          children: [
            _Thumb(file: file, colors: colors, gateway: gateway),
            const SizedBox(width: 10),
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
                  Text(
                    file.caption,
                    style: DsTypography.codeBlockLabel.copyWith(
                      color: colors.labelTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.more_horiz, size: 18, color: colors.labelTertiary),
          ],
        ),
      ),
    );
  }
}

/// 40×40 缩略图：图片走网关取字节，其余用类型图标。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.colors, required this.gateway});

  final ArtifactFile file;
  final DsColors colors;
  final GatewayClient? gateway;

  static final Map<String, Future<Uint8List?>> _cache = {};

  Future<Uint8List?> _bytes() {
    final client = gateway;
    if (client == null || file.kind != ArtifactKind.image) {
      return Future<Uint8List?>.value(null);
    }
    return _cache.putIfAbsent(file.path, () async {
      try {
        final resolved = await gatewayResolvePath(client, file.path);
        final raw = await gatewayReadFileBytes(
          client,
          resolved.rootId,
          resolved.path,
        );
        return Uint8List.fromList(raw);
      } on Exception {
        return null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.bgLayer2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderL1),
      ),
      child: Icon(
        _iconOf(file.kind),
        size: 18,
        color: colors.labelTertiary,
      ),
    );
    if (file.kind != ArtifactKind.image || gateway == null) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: _bytes(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            cacheWidth: 120,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
          ),
        );
      },
    );
  }

  static IconData _iconOf(ArtifactKind kind) => switch (kind) {
    ArtifactKind.image => Icons.image_outlined,
    ArtifactKind.pdf => Icons.picture_as_pdf_outlined,
    ArtifactKind.document => Icons.description_outlined,
    ArtifactKind.spreadsheet => Icons.table_chart_outlined,
    ArtifactKind.slides => Icons.slideshow_outlined,
    ArtifactKind.archive => Icons.folder_zip_outlined,
    ArtifactKind.audio => Icons.audiotrack_outlined,
    ArtifactKind.video => Icons.movie_outlined,
    ArtifactKind.web => Icons.language,
    ArtifactKind.markdown => Icons.article_outlined,
    ArtifactKind.text => Icons.notes_outlined,
    ArtifactKind.other => Icons.insert_drive_file_outlined,
  };
}
