// 输入条的单行 ⇄ 双行排布（part of composer.dart）。
part of 'composer.dart';

/// 输入条「单行胶囊 ⇄ 双行展开」的排布（对照 dsh-go
/// `dsh-Go/app/lib/ui/chat/composer.dart` 里的 `_ComposerRows`）。
///
/// 收起和展开共用同一棵树，只改几何：
///
/// ```
/// 收起（没有输入）                              展开（有文字 / 待发图片）
/// ┌────────────────────────────┐          ┌──────────────────────────────┐
/// │ (+)  text…         (环) (↑) │   →      │ text…                        │
/// └────────────────────────────┘          │ (+) [模型/图片/展开]  (环) (↑) │
///                                         └──────────────────────────────┘
/// ```
///
/// children 固定四个：`[text, leading, footer, trailing]`。数字 0→1 时文字从
/// 「(键)文字(键)」的中间位置补间到自己的整行，键行贴到底边；footer 只在
/// 展开过半后参与绘制/命中/语义（收起态它没有位置，也没有高度）。
class _ComposerRows extends MultiChildRenderObjectWidget {
  const _ComposerRows({required this.open, required super.children});

  /// 0 = 单行收起，1 = 双行展开。
  final Animation<double> open;

  @override
  _RenderComposerRows createRenderObject(BuildContext context) {
    return _RenderComposerRows(open);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderComposerRows renderObject,
  ) {
    renderObject.open = open;
  }
}

class _ComposerRowsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderComposerRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ComposerRowsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ComposerRowsParentData> {
  _RenderComposerRows(this._open);

  /// 收起态：文字与左侧键之间的空隙。
  static const double _gap = 8.0;

  /// 展开态：文字与键行之间的空隙。
  static const double _rowGap = DsSpacing.composerKeyGap;

  /// 展开态：文字左右内边距。
  static const double _inset = DsSpacing.composerTextInset;

  Animation<double> _open;

  set open(Animation<double> value) {
    if (identical(value, _open)) return;
    if (attached) _open.removeListener(markNeedsLayout);
    _open = value;
    if (attached) _open.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  double get _t => _open.value;

  /// 展开过半才让 footer 参与绘制/命中/语义（dsh-go 的 `_footerLive`）。
  bool get _footerLive => _t > 0.5;

  RenderBox get _text => firstChild!;

  RenderBox get _leading => childAfter(_text)!;

  RenderBox get _footer => childAfter(_leading)!;

  RenderBox get _trailing => childAfter(_footer)!;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _open.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _open.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ComposerRowsParentData) {
      child.parentData = _ComposerRowsParentData();
    }
  }

  /// 文字宽度：收起态让出左右键的位置，展开态占满整行（减 [_inset]）。
  double _textWidth(double width, double leading, double trailing) {
    final rest = width - (leading > 0 ? leading + _gap : 0) - _gap - trailing;
    return math.max(0.0, ui.lerpDouble(rest, width - 2 * _inset, _t)!);
  }

  Size _measure(BoxConstraints constraints, ChildLayouter layoutChild) {
    final width = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: width);
    final lead = layoutChild(_leading, loose);
    final trail = layoutChild(_trailing, loose);
    final foot = layoutChild(
      _footer,
      BoxConstraints(
        maxWidth: math.max(0.0, width - lead.width - trail.width - 2 * _rowGap),
      ),
    );
    final field = layoutChild(
      _text,
      BoxConstraints.tightFor(width: _textWidth(width, lead.width, trail.width)),
    );
    final keys = math.max(math.max(lead.height, trail.height), foot.height);
    final height = ui.lerpDouble(
      math.max(field.height, keys),
      field.height + _rowGap + keys,
      _t,
    )!;
    return constraints.constrain(Size(width, height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return _measure(constraints, ChildLayoutHelper.dryLayoutChild);
  }

  @override
  void performLayout() {
    size = _measure(constraints, ChildLayoutHelper.layoutChild);
    final t = _t;

    void place(RenderBox child, double x, double y) {
      (child.parentData! as _ComposerRowsParentData).offset = Offset(x, y);
    }

    final restX = _leading.size.width > 0 ? _leading.size.width + _gap : 0.0;
    final keys = math.max(
      math.max(_leading.size.height, _trailing.size.height),
      _footer.size.height,
    );
    // 收起态文字在单行里居中；展开态顶到第一行行首。
    final restTop = math.max(0.0, (keys - _text.size.height) / 2);
    place(_text, ui.lerpDouble(restX, _inset, t)!, ui.lerpDouble(restTop, 0, t)!);

    double centred(RenderBox child) => size.height - keys + (keys - child.size.height) / 2;
    place(_leading, 0, centred(_leading));
    place(_footer, _leading.size.width + _rowGap, centred(_footer));
    place(_trailing, size.width - _trailing.size.width, centred(_trailing));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      if (identical(child, _footer) && !_footerLive) continue;
      context.paintChild(
        child,
        (child.parentData! as _ComposerRowsParentData).offset + offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final footer = _footer;
    for (RenderBox? child = lastChild; child != null; child = childBefore(child)) {
      final box = child;
      if (identical(box, footer) && !_footerLive) continue;
      final offset = (box.parentData! as _ComposerRowsParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) => box.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final footer = _footer;
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      if (identical(child, footer) && !_footerLive) continue;
      visitor(child);
    }
  }
}
