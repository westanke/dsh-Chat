// 会话页外壳：顶栏 / 正文 / 输入条 / 渐隐带四个槽位。
//
// 结构借自 dsh-go 的 `_ChatLayout`（app/lib/ui/chat/chat_screen.dart）：输入条先量高度，
// 正文区因此伸到输入条上沿以下一点，底部一条渐隐带盖住交界处，文字滑到输入条后面时
// 淡出而不是被裁一刀。配色与既有控件仍用本仓 token。

library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'window_class.dart';

/// 外壳的四个槽位。
enum ChatShellSlot { body, veil, header, composer }

/// 会话页外壳。
class ChatShell extends StatefulWidget {
  const ChatShell({
    super.key,
    required this.colors,
    required this.header,
    required this.body,
    required this.composer,
  });

  final DsColors colors;

  /// 顶栏（自带顶部安全区）。
  final Widget header;

  /// 正文（列表 / 空态）。
  final Widget body;

  /// 输入条。
  final Widget composer;

  @override
  State<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends State<ChatShell> {
  /// 渐隐带实心部分的高度（= 输入条高度减去重叠量）。布局时写入，绘制时读。
  final ValueNotifier<double> _veilSolid = ValueNotifier<double>(0);

  @override
  void dispose() {
    _veilSolid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return CustomMultiChildLayout(
      delegate: ChatShellLayout(colors: c, veilSolid: _veilSolid),
      children: [
        LayoutId(
          id: ChatShellSlot.body,
          child: Builder(
            builder: (context) => MediaQuery.removePadding(
              // 顶栏自己吃掉顶部安全区，正文不再重复留白。
              context: context,
              removeTop: true,
              child: widget.body,
            ),
          ),
        ),
        LayoutId(
          id: ChatShellSlot.veil,
          child: IgnorePointer(
            child: _Veil(colors: c, solidHeight: _veilSolid),
          ),
        ),
        LayoutId(id: ChatShellSlot.header, child: widget.header),
        LayoutId(
          id: ChatShellSlot.composer,
          child: _ComposerSlot(colors: c, child: widget.composer),
        ),
      ],
    );
  }
}

/// 分槽布局：先量输入条 → 再量顶栏 → 正文填中间。
class ChatShellLayout extends MultiChildLayoutDelegate {
  ChatShellLayout({required this.colors, required this.veilSolid});

  final DsColors colors;

  /// 渐隐带实心高度（布局时写、绘制时读）。
  final ValueNotifier<double> veilSolid;

  @override
  void performLayout(Size size) {
    final width = size.width;
    // 高度无界：各槽按内容收缩包裹。
    final along = BoxConstraints(minWidth: width, maxWidth: width);

    final composer = layoutChild(ChatShellSlot.composer, along);
    final composerTop = size.height - composer.height;
    positionChild(ChatShellSlot.composer, Offset(0, composerTop));

    final header = layoutChild(ChatShellSlot.header, along);
    positionChild(ChatShellSlot.header, Offset.zero);

    // 正文伸到输入条上沿以下 chatListOverlap：底色在那里已经是实心，看不见裁切。
    final bodyTop = header.height;
    final bodyHeight = math.max(
      0.0,
      composerTop + DsSpacing.chatListOverlap - bodyTop,
    );
    layoutChild(
      ChatShellSlot.body,
      BoxConstraints.tight(Size(width, bodyHeight)),
    );
    positionChild(ChatShellSlot.body, Offset(0, bodyTop));

    // 渐隐带：实心部分托住输入条，往上羽化一段。
    final solid = math.max(0.0, composer.height - DsSpacing.chatListOverlap);
    veilSolid.value = solid;
    final veilHeight = solid + DsSpacing.chatVeilFeather;
    layoutChild(
      ChatShellSlot.veil,
      BoxConstraints.tight(Size(width, veilHeight)),
    );
    positionChild(ChatShellSlot.veil, Offset(0, size.height - veilHeight));
  }

  @override
  bool shouldRelayout(covariant ChatShellLayout oldDelegate) =>
      oldDelegate.colors != colors;
}

/// 底部渐隐带：上沿羽化一段，往下是实心底色。
class _Veil extends StatelessWidget {
  const _Veil({required this.colors, required this.solidHeight});

  final DsColors colors;
  final ValueListenable<double> solidHeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _VeilPainter(colors: colors, solidHeight: solidHeight),
    );
  }
}

class _VeilPainter extends CustomPainter {
  _VeilPainter({required this.colors, required this.solidHeight})
    : super(repaint: solidHeight);

  final DsColors colors;
  final ValueListenable<double> solidHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    final feather = DsSpacing.chatVeilFeather;
    // 实心区从下往上占 solidHeight，往上是羽化带。
    final solidTop = math.max(0.0, size.height - solidHeight.value);
    if (solidTop <= 0) return;
    final featherBand = math.min(feather, solidTop);
    final rect = Rect.fromLTWH(
      0,
      solidTop - featherBand,
      size.width,
      size.height - (solidTop - featherBand),
    );
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [colors.bgBase.withValues(alpha: 0), colors.bgBase],
      stops: const [0, 1],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _VeilPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

/// 输入条槽：底部安全区 + 浮层列宽（§4.16：可读列两侧各窄 chatFloatInset）。
class _ComposerSlot extends StatelessWidget {
  const _ComposerSlot({required this.colors, required this.child});

  final DsColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: DsSpacing.chatComposerBottomPad),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 按实际拿到的宽度算：抽屉打开时页面缩窄，输入条跟着收。
          // 手机上没有富余，floatingColumnWidth 返回屏宽，与改动前一致。
          final columnMax = floatingColumnWidth(constraints.maxWidth);
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: columnMax),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
