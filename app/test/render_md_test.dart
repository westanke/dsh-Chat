/// 把 Markdown 全家福离屏渲染成 PNG，便于在宿主上直接和官方截图逐项比对（不装机）。
/// 用法：flutter test test/render_md_test.dart
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/md_view.dart';
import 'package:flutter/services.dart' show BasicMessageChannel, JSONMessageCodec;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _demo = '''
# H1 Heading
## H2 Heading
### H3 Heading

Normal paragraph text with **bold**, *italic*, ~~strike~~ and `inline code`.

- Bullet one
- Bullet two
  - Nested bullet

1. First item
2. Second item
   - Nested bullet under the second

[x] Completed task
[ ] Pending task

```python
def greet(name):
    return f"Hello, {name}!"
```

| A | B | C |
|---|---|---|
| 1 | 2 | 3 |
| 4 | 5 | 6 |

> This is a blockquote.

---

Inline math: \$\\frac{a}{b}\$ sits on this line.

[example link](https://example.com)
''';

void main() {
  testWidgets('导出 Markdown 全家福 PNG', (tester) async {
    // Flutter 3.50：teardown 期间会派发 fontsChange（flutter/system channel），
    // 树卸载后 RelayoutWhenSystemFontsChange 仍调度帧回调 → postTest 判
    // 「animation still running」。setMockMessageHandler 会在 postTest 被清掉
    // 拦不住，这里真实替换 handler 吞掉系统消息（本文件仅此一个测试，
    // flutter test 每文件独立进程，不影响其他测试）。
    const BasicMessageChannel<dynamic>(
      'flutter/system',
      JSONMessageCodec(),
    ).setMessageHandler((message) async {});
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          body: RepaintBoundary(
            child: Container(
              width: 360,
              color: const Color(0xFFFFFFFF),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: const DsMarkdownView(
                text: _demo,
                colors: DsColors(false),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    late final ByteData? bytes;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    });
    // 输出到仓库的 ref/，用**相对路径**：`flutter test` 的工作目录是 app/，
    // 所以 ../ref 即仓库根的 ref/。早先这里写死 /media/wangke/... 绝对路径，
    // 换机器或进 CI 必然失败（那个目录在 CI 里根本不存在，writeAsBytesSync 抛异常）。
    final refDir = Directory('../ref');
    expect(refDir.existsSync(), isTrue,
        reason: 'ref/ 应随仓库分发；缺失说明 .gitignore 误伤了基准素材');
    final out = File('${refDir.path}/md-preview.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(out.existsSync(), isTrue);
  });
}
