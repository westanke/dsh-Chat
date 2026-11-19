/// Markdown 视图渲染冒烟测试：断言官方 MD 全家福在 360dp 宽度下不溢出。
library;

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/md_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _demo = '''
# H1
## H2
### H3

- 项目一
- 项目二

1. 第一
2. 第二

- [x] 已完成
- [ ] 待办

**粗体** *斜体* ~~删除线~~ `inline`

```python
print("hi")
```

| A | B | C |
|---|---|---|
| 1 | 2 | 3 |
| 4 | 5 | 6 |

> 引用

---

[链接](https://example.com)
''';

Widget _host(String text) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          // 官方窄屏下限：360dp 逻辑宽度。
          width: 360,
          child: SingleChildScrollView(
            child: DsMarkdownView(text: text, colors: DsColors(false)),
          ),
        ),
      ),
    );

void main() {
  testWidgets('MD 全家福不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_demo));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('超长表格不溢出（横向滚动或裁切）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final wide = '| ${List.generate(8, (i) => 'col$i').join(' | ')} |\n'
        '|${List.filled(8, '---').join('|')}|\n'
        '| ${List.generate(8, (i) => 'value $i long text').join(' | ')} |';
    await tester.pumpWidget(_host(wide));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  test('表格紧贴段落时补空行（GFM 允许，引擎不认）', () {
    const glued = '下面是结果：\n| A | B |\n| --- | --- |\n| 1 | 2 |';
    final fixed = normalizeTables(glued);
    expect(fixed.split('\n').take(3).toList(),
        ['下面是结果：', '', '| A | B |']);
    // 单元格内容一个字都不动
    expect(fixed.replaceAll('\n', ''), glued.replaceAll('\n', ''));
  });

  test('表格前本来就有空行 / 表格连续行 → 不重复插空行', () {
    const ok = '段落\n\n| A | B |\n| --- | --- |\n| 1 | 2 |';
    expect(normalizeTables(ok), ok);
    expect('| A |\n| --- |'.split('\n').length,
        normalizeTables('| A |\n| --- |').split('\n').length);
  });

  test('围栏代码块里的竖线不算表格（整段原样保留）', () {
    const code = '看这个：\n```\n| A | B |\n|---|---|\n```';
    expect(normalizeTables(code), code);
    const tilde = '看这个：\n~~~md\n| A |\n~~~';
    expect(normalizeTables(tilde), tilde);
  });

  test('没有竖线 → 原样返回（不扫全篇）', () {
    expect(normalizeTables('纯文本\n第二行'), '纯文本\n第二行');
  });
}
