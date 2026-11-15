/// MdParser / MdInline / LatexLite / SimpleHighlight 单测（node:test 直测 core）。
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { parseMarkdown, MD_P, MD_H, MD_CODE, MD_QUOTE, MD_UL, MD_OL, MD_TABLE, MD_HR, MD_LATEX }
  from '../../entry/src/main/ets/core/MdParser.ts';
import { parseInline } from '../../entry/src/main/ets/core/MdInline.ts';
import { parseLatex, splitLatex, flattenText }
  from '../../entry/src/main/ets/core/LatexLite.ts';
import { highlight }
  from '../../entry/src/main/ets/core/SimpleHighlight.ts';

describe('MdParser 块级', () => {
  test('空输入与纯空白', () => {
    assert.equal(parseMarkdown('').length, 0);
    assert.equal(parseMarkdown('\n\n  \n').length, 0);
  });

  test('标题 1-6 级', () => {
    const blocks = parseMarkdown('# 一\n## 二\n###### 六');
    assert.equal(blocks.length, 3);
    assert.equal(blocks[0].type, MD_H);
    assert.equal(blocks[0].level, 1);
    assert.equal(blocks[0].text, '一');
    assert.equal(blocks[2].level, 6);
  });

  test('围栏代码闭合', () => {
    const blocks = parseMarkdown('```python\nprint(1)\n```');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, MD_CODE);
    assert.equal(blocks[0].lang, 'python');
    assert.equal(blocks[0].text, 'print(1)');
  });

  test('围栏代码流式未闭合', () => {
    const blocks = parseMarkdown('```bash\necho hi');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, MD_CODE);
    assert.equal(blocks[0].text, 'echo hi');
  });

  test('引用块', () => {
    const blocks = parseMarkdown('> 引用一\n> 引用二');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, MD_QUOTE);
    assert.equal(blocks[0].text, '引用一\n引用二');
  });

  test('无序列表与任务列表', () => {
    const blocks = parseMarkdown('- 普通项\n- [x] 已完成\n* [ ] 未完成');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, MD_UL);
    assert.equal(blocks[0].items.length, 3);
    assert.equal(blocks[0].items[0].checked, -1);
    assert.equal(blocks[0].items[1].checked, 1);
    assert.equal(blocks[0].items[1].text, '已完成');
    assert.equal(blocks[0].items[2].checked, 0);
  });

  test('有序列表', () => {
    const blocks = parseMarkdown('1. 第一\n2. 第二');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, MD_OL);
    assert.equal(blocks[0].items[1].text, '第二');
  });

  test('表格含对齐', () => {
    const md = '| A | B |\n|:--|--:|\n| 1 | 2 |';
    const blocks = parseMarkdown(md);
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, MD_TABLE);
    // rows = 表头 + 数据行（分隔行只贡献对齐，不进 rows）
    assert.equal(blocks[0].rows.length, 2);
    assert.deepEqual(blocks[0].rows[0], ['A', 'B']);
    assert.deepEqual(blocks[0].rows[1], ['1', '2']);
    assert.equal(blocks[0].align[0], 'l'); // :-- 左对齐
    assert.equal(blocks[0].align[1], 'r'); // --: 右对齐
  });

  test('分隔线', () => {
    const blocks = parseMarkdown('---\n***');
    assert.equal(blocks.length, 2);
    assert.equal(blocks[0].type, MD_HR);
    assert.equal(blocks[1].type, MD_HR);
  });

  test('块公式单行与多行', () => {
    const blocks = parseMarkdown('$$x^2 + 1$$');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, MD_LATEX);
    assert.equal(blocks[0].text, 'x^2 + 1');
    const multi = parseMarkdown('$$\n\\frac{a}{b}\n$$');
    assert.equal(multi.length, 1);
    assert.equal(multi[0].type, MD_LATEX);
    assert.equal(multi[0].text, '\\frac{a}{b}');
  });

  test('段落合并与后续块切断', () => {
    const md = '第一行\n第二行\n\n# 标题';
    const blocks = parseMarkdown(md);
    assert.equal(blocks.length, 2);
    assert.equal(blocks[0].type, MD_P);
    assert.equal(blocks[0].text, '第一行\n第二行');
    assert.equal(blocks[1].type, MD_H);
  });

  test('段落里的行内公式段', () => {
    const blocks = parseMarkdown('质能方程 $E=mc^2$ 很有名');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].segs.length, 3);
    assert.equal(blocks[0].segs[1].text, '$E=mc^2$');
  });
});

describe('MdInline 行内', () => {
  test('纯文本', () => {
    const segs = parseInline('普通文本');
    assert.equal(segs.length, 1);
    assert.equal(segs[0].text, '普通文本');
    assert.equal(segs[0].bold, false);
  });

  test('粗体与斜体', () => {
    const segs = parseInline('**加粗**和*斜体*');
    assert.equal(segs.length, 3);
    assert.equal(segs[0].text, '加粗');
    assert.equal(segs[0].bold, true);
    assert.equal(segs[1].text, '和');
    assert.equal(segs[2].italic, true);
  });

  test('行内代码', () => {
    const segs = parseInline('用 `npm test` 跑');
    assert.equal(segs.length, 3);
    assert.equal(segs[1].text, 'npm test');
    assert.equal(segs[1].code, true);
  });

  test('删除线', () => {
    const segs = parseInline('~~废弃~~');
    assert.equal(segs[0].strike, true);
  });

  test('链接与裸 URL', () => {
    const segs = parseInline('[文档](https://example.com/a)');
    assert.equal(segs.length, 1);
    assert.equal(segs[0].link, 'https://example.com/a');
    assert.ok(segs[0].text.indexOf('文档') >= 0);
    const bare = parseInline('看 https://a.b/c 就行');
    const urlSeg = bare.filter((s) => s.link.length > 0);
    assert.equal(urlSeg.length, 1);
    assert.equal(urlSeg[0].link, 'https://a.b/c');
  });

  test('嵌套：粗体里行内代码', () => {
    const segs = parseInline('**跑 `npm`**');
    assert.equal(segs.length, 2);
    assert.equal(segs[0].bold, true);
    assert.equal(segs[0].text, '跑 ');
    assert.equal(segs[1].code, true);
    assert.equal(segs[1].bold, true);
  });
});

describe('LatexLite', () => {
  test('文本与符号', () => {
    const n = parseLatex('a + \\beta');
    assert.equal(flattenText(n), 'a+β');
  });

  test('分数', () => {
    const n = parseLatex('\\frac{a+b}{c}');
    assert.equal(n.kind, 'frac');
    assert.equal(flattenText(n.num), 'a+b');
    assert.equal(flattenText(n.den), 'c');
  });

  test('根号与上下标', () => {
    const n = parseLatex('\\sqrt{x}^2_a');
    const flat = flattenText(n);
    assert.ok(flat.indexOf('√') >= 0);
    const parts = parseLatex('x^2');
    // x^2 解析为 row：[text x, sup 2]
    assert.equal(parts.kind, 'row');
    assert.equal(parts.children.length, 2);
    assert.equal(parts.children[1].kind, 'sup');
    assert.equal(flattenText(parts.children[1].arg), '2');
    const sub = parseLatex('x_i');
    assert.equal(sub.kind, 'row');
    assert.equal(sub.children[1].kind, 'sub');
    assert.equal(flattenText(sub.children[1].arg), 'i');
  });

  test('未知命令回退原文', () => {
    const n = parseLatex('\\unknowncmd{x}');
    assert.ok(flattenText(n).indexOf('\\unknowncmd') >= 0);
  });

  test('嵌套分数', () => {
    const n = parseLatex('\\frac{\\frac{a}{b}}{c}');
    assert.equal(n.kind, 'frac');
    assert.equal(flattenText(n.num), '(a)/(b)');
    assert.equal(flattenText(n.den), 'c');
  });

  test('splitLatex：行内优先于普通文本', () => {
    const segs = splitLatex('值 $x_1$ 与 $$y^2$$');
    assert.equal(segs.length, 4);
    assert.equal(segs[0].latex, false);
    assert.equal(segs[1].latex, true);
    assert.equal(segs[1].block, false);
    assert.equal(segs[1].text, 'x_1');
    assert.equal(segs[2].latex, false);
    assert.equal(segs[3].latex, true);
    assert.equal(segs[3].block, true);
    assert.equal(segs[3].text, 'y^2');
  });

  test('splitLatex：无公式原样', () => {
    const segs = splitLatex('普通文本');
    assert.equal(segs.length, 1);
    assert.equal(segs[0].latex, false);
    assert.equal(segs[0].text, '普通文本');
  });
});

describe('SimpleHighlight', () => {
  test('python：注释/关键词/字符串/数字', () => {
    const rows = highlight('x = 1  # 注释\nprint("hi")', 'python');
    assert.equal(rows.length, 2);
    const row0 = rows[0];
    assert.equal(row0[0].text, 'x = ');
    const num = row0.filter((s) => s.cls === 'num');
    assert.equal(num.length, 1);
    assert.equal(num[0].text, '1');
    const cmt = row0.filter((s) => s.cls === 'comment');
    assert.equal(cmt.length, 1);
    assert.equal(cmt[0].text, '# 注释');
    const row1 = rows[1];
    const kw = row1.filter((s) => s.cls === 'kw');
    assert.equal(kw.length, 1);
    assert.equal(kw[0].text, 'print');
    const str = row1.filter((s) => s.cls === 'str');
    assert.equal(str[0].text, '"hi"');
  });

  test('字符串里的注释符不算注释', () => {
    const rows = highlight('s = "a#b"', 'python');
    const cmt = rows[0].filter((s) => s.cls === 'comment');
    assert.equal(cmt.length, 0);
    const str = rows[0].filter((s) => s.cls === 'str');
    assert.equal(str[0].text, '"a#b"');
  });

  test('未知语言全 plain', () => {
    const rows = highlight('x = 1', 'brainfuck');
    assert.equal(rows[0].length, 1);
    assert.equal(rows[0][0].cls, 'plain');
  });

  test('bash 注释符', () => {
    const rows = highlight('ls -la # 列目录', 'bash');
    const cmt = rows[0].filter((s) => s.cls === 'comment');
    assert.equal(cmt[0].text, '# 列目录');
  });
});
