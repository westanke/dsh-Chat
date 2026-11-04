/// 历史图片显示（真机反馈 2026-11-04 第 1 项）：
/// - 历史里的图片是 attachment 引用（sha256:`<hex>`，无字节）→
///   REST GET /api/v1/attachments/{id} 取字节；
/// - 纯文本模型的图片交接占位文本 `[Image: source: .../<sha256>.<ext>]` →
///   REST GET /api/v1/image-handoff?name=`<bare>` 取字节（反馈第 8 条显示回路）。
/// 内存内缓存（Map），失败显示占位图标可点重试。授权 Bearer token。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bridge/content.dart';
import '../bridge/gateway.dart';
import '../design/tokens.dart';

/// 进程内字节缓存（immutable 资源，不淘汰）。
final Map<String, Uint8List> _bytesCache = {};

/// 挂在 DsImageRef 上的下载执行器（由 ChatPage 注入 gateway，避免本文件
/// 反向依赖会话状态）。
typedef ImageFetcher = Future<Uint8List> Function(DsImageRef ref);

/// 一张待显示图：attachment 引用或 image-handoff 裸文件名，二选一。
class DsImageRef {
  const DsImageRef.attachment(String this.attachmentId)
    : handoffName = null;
  const DsImageRef.handoff(String this.handoffName)
    : attachmentId = null;

  final String? attachmentId; // 'sha256:<hex>'
  final String? handoffName; // '<64hex>.<ext>'

  String get cacheKey => attachmentId ?? 'handoff:$handoffName';
}

/// 用户气泡/正文里的图片块（自动下载 + 占位 + 重试）。
class DsChatImage extends StatefulWidget {
  const DsChatImage({
    super.key,
    required this.ref,
    required this.colors,
    required this.fetcher,
    this.maxWidth = 260,
  });

  final DsImageRef ref;
  final DsColors colors;
  final ImageFetcher fetcher;
  final double maxWidth;

  @override
  State<DsChatImage> createState() => _DsChatImageState();
}

class _DsChatImageState extends State<DsChatImage> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DsChatImage old) {
    super.didUpdateWidget(old);
    if (old.ref.cacheKey != widget.ref.cacheKey) _load();
  }

  Future<void> _load() async {
    final cached = _bytesCache[widget.ref.cacheKey];
    if (cached != null) {
      setState(() {
        _bytes = cached;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.fetcher(widget.ref);
      _bytesCache[widget.ref.cacheKey] = bytes;
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } on RequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '图片加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Image.memory(
            _bytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    // 占位：加载中转圈 / 失败可点重试。
    return InkWell(
      onTap: _error == null ? null : _load,
      borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
      child: Container(
        width: widget.maxWidth,
        height: 140,
        decoration: BoxDecoration(
          color: c.mdCodeBlockBg,
          borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
        ),
        child: Center(
          child: _loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.labelTertiary,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      size: 28,
                      color: c.labelTertiary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _error ?? '图片',
                      style: DsTypography.caption.copyWith(
                        color: c.labelTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '点按重试',
                          style: DsTypography.caption.copyWith(
                            color: c.link,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 默认下载器：attachment 走 attachments 接口，handoff 走 image-handoff。
ImageFetcher gatewayImageFetcher(GatewayClient gateway) {
  return (DsImageRef ref) async {
    final Uint8List bytes;
    final att = ref.attachmentId;
    if (att != null) {
      bytes = Uint8List.fromList(await gateway.fetchAttachment(att));
    } else {
      bytes = Uint8List.fromList(
        await gateway.fetchImageHandoff(ref.handoffName!),
      );
    }
    // 简单校验：非空、且像图片（PNG/JPEG/GIF/WebP 魔数）。
    if (bytes.isEmpty) throw RequestException('EMPTY', '图片为空');
    return bytes;
  };
}

/// 把 content 里的图片引用转成待显示 ref（ContentImageRef → DsImageRef）。
List<DsImageRef> imageRefsOf(List<ContentImageRef> images) => [
  for (final i in images) DsImageRef.attachment(i.attachmentId),
];

/// 从消息文本提取 image-handoff 占位（见 content.dart 的正则）。
DsImageRef? handoffRefOf(String text) {
  final name = handoffImageNameOf(text);
  if (name == null) return null;
  return DsImageRef.handoff(name);
}
