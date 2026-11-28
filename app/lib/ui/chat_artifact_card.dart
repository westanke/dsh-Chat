/// 本轮生成文件卡：「生成了 N 个文件」+ 缩略图 + 文件名 + 类型说明。
///
/// 对照 dsh-go（app/lib/ui/chat/widgets/artifact_card.dart）：最多列 4 行，
/// 超出的收进「全部 N 个文件」。缩略图只在图片且能取到字节时显示，取不到
/// 退回类型图标——不留一个永远空着的方块。
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../design/tokens.dart';
import 'file_open.dart';
import 'turn_changes.dart';

class ArtifactCard extends StatefulWidget {
  const ArtifactCard({
    super.key,
    required this.files,
    required this.colors,
    this.gateway,
    this.rootId,
  });

  final List<ArtifactFile> files;
  final DsColors colors;
  final GatewayClient? gateway;

  /// 当前会话工作区的授权根；拿不到就 null（桥落首个授权根）。
  final String? rootId;

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
              rootId: widget.rootId,
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
    required this.rootId,
  });

  final ArtifactFile file;
  final DsColors colors;
  final GatewayClient? gateway;
  final String? rootId;

  void _open(BuildContext context) {
    final client = gateway;
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接，无法打开文件')),
      );
      return;
    }
    openWorkspaceFile(
      context,
      gateway: client,
      path: file.path,
      name: file.name,
      colors: colors,
    );
  }

  void _share(BuildContext context) {
    final client = gateway;
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接，无法分享文件')),
      );
      return;
    }
    shareWorkspaceFile(
      context,
      gateway: client,
      path: file.path,
      name: file.name,
    );
  }

  /// 同目录下的新路径（`file.path` 原样保留目录部分）。
  String _siblingPath(String name) {
    final slash = file.path.lastIndexOf('/');
    return slash < 0 ? name : '${file.path.substring(0, slash + 1)}$name';
  }

  Future<void> _rename(BuildContext context) async {
    final client = gateway;
    if (client == null) {
      _toast(context, '未连接，无法重命名');
      return;
    }
    var input = file.name;
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextFormField(
          initialValue: file.name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '文件名'),
          onChanged: (v) => input = v,
          onFieldSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, input),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    final name = (entered ?? '').trim();
    if (name.isEmpty || name == file.name) return;
    try {
      await client.renameFile(
        rootId: rootId,
        from: file.path,
        to: _siblingPath(name),
      );
    } on RequestException catch (e) {
      if (context.mounted) _toast(context, '重命名失败：${e.message}');
      return;
    }
    if (context.mounted) _toast(context, '已重命名');
  }

  Future<void> _delete(BuildContext context) async {
    final client = gateway;
    if (client == null) {
      _toast(context, '未连接，无法移到回收站');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移到回收站？'),
        content: Text('「${file.name}」将移入回收站，可在回收站恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移到回收站'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await client.moveFileToTrash(rootId: rootId, path: file.path);
    } on RequestException catch (e) {
      if (context.mounted) _toast(context, '移到回收站失败：${e.message}');
      return;
    }
    if (context.mounted) _toast(context, '已移入回收站');
  }

  Future<void> _showMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开 / 预览'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制路径'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('分享文件'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            if (gateway?.hasFrame('file-rename') == true)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('重命名'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
            if (gateway?.hasFrame('file-delete') == true)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('移到回收站'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'open':
        _open(context);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: file.path));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制路径')),
        );
      case 'share':
        _share(context);
      case 'rename':
        await _rename(context);
      case 'delete':
        await _delete(context);
      default:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
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
            InkWell(
              onTap: () => _showMenu(context),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: colors.labelTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 文件操作结果统一走 SnackBar（失败也走这里，文案带桥的 message）。
void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
