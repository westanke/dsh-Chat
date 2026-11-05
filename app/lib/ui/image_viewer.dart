/// 全屏图片查看器（真机反馈第四轮 1）：黑底 + InteractiveViewer
/// 双指缩放/拖移，点空白处或关闭钮退出，双击在 1x/2.5x 间切换。
/// 独立路由页（不走聊天页布局），字节由调用方传入（已在缓存，零请求）。
/// 独立库（chat_page 与 chat_image 都要调用，不能挂成单边 part）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<void> openImageViewer(
  BuildContext context, {
  required Uint8List bytes,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      // 淡入 + 黑底：比 MaterialPageRoute 更像图片查看器（无 AppBar 走廊感）。
      opaque: false,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _ImageViewerPage(bytes: bytes),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _ImageViewerPage extends StatefulWidget {
  const _ImageViewerPage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  final _controller = TransformationController();
  TapDownDetails? _lastTapDown;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final current = _controller.value.getMaxScaleOnAxis();
    if (current > 1.5) {
      // 已放大 → 回 1x。
      _controller.value = Matrix4.identity();
    } else {
      // 1x → 放大到 2.5x，以双击位置为中心。
      final pos = _lastTapDown?.localPosition ?? const Offset(0, 0);
      _controller.value = Matrix4.identity()
        ..translateByDouble(-pos.dx * 1.5, -pos.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 点击空白关闭：GestureDetector 包在 InteractiveViewer 外，
          // 单击（不拖动）时收到 onTap。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            onDoubleTapDown: (d) => _lastTapDown = d,
            onDoubleTap: _handleDoubleTap,
            child: Center(
              child: InteractiveViewer(
                transformationController: _controller,
                maxScale: 8,
                minScale: 1,
                boundaryMargin: const EdgeInsets.all(80),
                child: Image.memory(widget.bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
