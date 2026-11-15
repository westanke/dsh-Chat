/// 轻量 LaTeX 渲染 —— 公式结构解析（纯逻辑，node 直测）。
/// 用户拍板（2026-11-15）：公式渲染首版就上轻量 LaTeX，不降级。
/// 范围：\frac \sqrt 上下标 希腊字母 常用运算符；嵌套支持一层递归；
/// 未知命令回退为去掉反斜杠的原文本——绝不抛异常、绝不炸渲染。
/// ArkTS 口径：扁平 class + kind 分派（禁判别联合），字段全默认值。

export class LatexNode {
  kind: string = 'text'; // text | frac | sqrt | sup | sub | sym | row
  text: string = '';
  children: LatexNode[] = [];
  num: LatexNode | null = null;
  den: LatexNode | null = null;
  arg: LatexNode | null = null;
}

/// 符号表（小写希腊 + 大写常用 + 运算符/箭头/杂项）。
const SYMBOLS: Map<string, string> = new Map<string, string>([
  ['alpha', 'α'], ['beta', 'β'], ['gamma', 'γ'], ['delta', 'δ'],
  ['epsilon', 'ε'], ['varepsilon', 'ε'], ['zeta', 'ζ'], ['eta', 'η'],
  ['theta', 'θ'], ['iota', 'ι'], ['kappa', 'κ'], ['lambda', 'λ'],
  ['mu', 'μ'], ['nu', 'ν'], ['xi', 'ξ'], ['pi', 'π'], ['rho', 'ρ'],
  ['sigma', 'σ'], ['tau', 'τ'], ['upsilon', 'υ'], ['phi', 'φ'],
  ['varphi', 'φ'], ['chi', 'χ'], ['psi', 'ψ'], ['omega', 'ω'],
  ['Gamma', 'Γ'], ['Delta', 'Δ'], ['Theta', 'Θ'], ['Lambda', 'Λ'],
  ['Xi', 'Ξ'], ['Pi', 'Π'], ['Sigma', 'Σ'], ['Phi', 'Φ'], ['Psi', 'Ψ'],
  ['Omega', 'Ω'],
  ['times', '×'], ['div', '÷'], ['pm', '±'], ['mp', '∓'],
  ['leq', '≤'], ['geq', '≥'], ['neq', '≠'], ['approx', '≈'],
  ['equiv', '≡'], ['sim', '∼'], ['propto', '∝'],
  ['sum', '∑'], ['prod', '∏'], ['int', '∫'], ['partial', '∂'],
  ['nabla', '∇'], ['infty', '∞'], ['cdot', '·'], ['cdots', '⋯'],
  ['ldots', '…'], ['vdots', '⋮'],
  ['in', '∈'], ['notin', '∉'], ['subset', '⊂'], ['supset', '⊃'],
  ['subseteq', '⊆'], ['supseteq', '⊇'], ['cup', '∪'], ['cap', '∩'],
  ['emptyset', '∅'], ['forall', '∀'], ['exists', '∃'],
  ['rightarrow', '→'], ['leftarrow', '←'], ['to', '→'],
  ['Rightarrow', '⇒'], ['Leftarrow', '⇐'], ['leftrightarrow', '↔'],
  ['Leftrightarrow', '⇔'], ['mapsto', '↦'], ['uparrow', '↑'],
  ['downarrow', '↓'],
  ['prime', '′'], ['deg', '°'], ['angle', '∠'], ['perp', '⊥'],
  ['parallel', '∥'], ['because', '∵'], ['therefore', '∴'],
  ['star', '⋆'], ['ast', '∗'], ['circ', '∘'], ['bullet', '•'],
  ['oplus', '⊕'], ['otimes', '⊗'], ['sqrt', '√'],
  ['langle', '⟨'], ['rangle', '⟩'], ['lceil', '⌈'], ['rceil', '⌉'],
  ['lfloor', '⌊'], ['rfloor', '⌋'],
  ['text', ''], ['mathrm', ''], ['mathbf', ''], ['mathit', ''],
  ['left', ''], ['right', ''], ['quad', '　'], ['qquad', '　　'],
  [',', '　'], [';', '　'], [' ', '　'],
]);

function newNode(kind: string): LatexNode {
  const n = new LatexNode();
  n.kind = kind;
  return n;
}

/// 解析整段 LaTeX 源（已剥 $$/$ 定界符）→ 节点树。
/// 解析永不失败：残缺输入尽量收敛，尾部未消费文本进 row。
export function parseLatex(src: string): LatexNode {
  const row = newNode('row');
  let i = 0;
  while (i < src.length) {
    const ch = src[i];
    if (ch === '\\') {
      i = readCommand(src, i + 1, row);
    } else if (ch === '^' || ch === '_') {
      i = readScript(src, i + 1, row, ch === '^' ? 'sup' : 'sub');
    } else if (ch === '{' || ch === '}') {
      i += 1; // 裸花括号：结构符直接吞掉（内容已由命令/脚本消费）
    } else if (ch === ' ' || ch === '\t') {
      i += 1;
    } else {
      // 连续普通字符合并成一个 text 节点
      let j = i;
      while (j < src.length && '{^}_\\ \t'.indexOf(src[j]) < 0) {
        j += 1;
      }
      const t = newNode('text');
      t.text = src.substring(i, j);
      row.children.push(t);
      i = j;
    }
  }
  return simplify(row);
}

/// 读一条 \command（含 {} 参数），把产物塞进 row。
/// 返回新的下标。
function readCommand(src: string, start: number, row: LatexNode): number {
  if (start >= src.length) {
    return start;
  }
  // \, \; \ 这类单字符命令
  const name0 = src[start];
  if (!/^[a-zA-Z]+$/.test(name0)) {
    const mapped = SYMBOLS.get(name0);
    const s = newNode('sym');
    s.text = mapped !== undefined ? mapped : name0;
    row.children.push(s);
    return start + 1;
  }
  let end = start;
  while (end < src.length && /[a-zA-Z]/.test(src[end])) {
    end += 1;
  }
  const name = src.substring(start, end);
  if (name === 'frac') {
    const num = readGroup(src, end);
    if (num === null) {
      return fallbackText(row, '\\' + name, end);
    }
    const den = readGroup(src, num.next);
    if (den === null) {
      const f = newNode('frac');
      f.num = num.node;
      f.den = plainNode('?');
      row.children.push(f);
      return num.next;
    }
    const f = newNode('frac');
    f.num = num.node;
    f.den = den.node;
    row.children.push(f);
    return den.next;
  }
  if (name === 'sqrt') {
    const g = readGroup(src, end);
    if (g === null) {
      return fallbackText(row, '\\' + name, end);
    }
    const s = newNode('sqrt');
    s.arg = g.node;
    row.children.push(s);
    return g.next;
  }
  // \text{...} / \mathrm{...}：内容按普通文本（剥格式）收进 row
  if (name === 'text' || name === 'mathrm' || name === 'mathbf' || name === 'mathit') {
    const g = readGroup(src, end);
    if (g === null) {
      return fallbackText(row, '\\' + name, end);
    }
    const t = newNode('text');
    t.text = flattenText(g.node);
    row.children.push(t);
    return g.next;
  }
  const mapped = SYMBOLS.get(name);
  if (mapped !== undefined) {
    if (mapped.length > 0) {
      const s = newNode('sym');
      s.text = mapped;
      row.children.push(s);
    } // 空映射（text/left/right 等排版命令）：只吞不产
    return end;
  }
  // 未知命令：原文（含反斜杠）照出，不中断
  const t = newNode('text');
  t.text = '\\' + name;
  row.children.push(t);
  return end;
}

/// 读一个 {...} 组（支持嵌套）；无组回 null。
function readGroup(src: string, at: number): { node: LatexNode, next: number } | null {
  let i = at;
  while (i < src.length && src[i] === ' ') {
    i += 1;
  }
  if (i >= src.length || src[i] !== '{') {
    // \frac ab 这种无括号单字符参数
    if (i < src.length && /[^{}\s]/.test(src[i])) {
      const n = parseLatex(src[i]);
      return { node: n, next: i + 1 };
    }
    return null;
  }
  let depth = 0;
  const inner = newNode('row');
  i += 1;
  const start = i;
  while (i < src.length) {
    const ch = src[i];
    if (ch === '{') {
      depth += 1;
    } else if (ch === '}') {
      if (depth === 0) {
        const body = src.substring(start, i);
        return { node: mergeRow(inner, body), next: i + 1 };
      }
      depth -= 1;
    }
    i += 1;
  }
  // 未闭合：吃到底
  const body = src.substring(start);
  return { node: mergeRow(inner, body), next: src.length };
}

function mergeRow(inner: LatexNode, body: string): LatexNode {
  const parsed = parseLatex(body);
  if (parsed.kind === 'row') {
    for (const c of parsed.children) {
      inner.children.push(c);
    }
  } else {
    // simplify 把单子 row 降级成了叶节点（text/frac/sup…），整颗塞回
    inner.children.push(parsed);
  }
  return simplify(inner);
}

function plainNode(text: string): LatexNode {
  const n = newNode('text');
  n.text = text;
  return n;
}

function fallbackText(row: LatexNode, text: string, next: number): number {
  row.children.push(plainNode(text));
  return next;
}

/// 读 ^{...} / _{...}（无括号取单字符），产物作为 sup/sub 塞进 row。
function readScript(src: string, at: number, row: LatexNode, kind: string): number {
  const g = readGroup(src, at);
  if (g === null) {
    return fallbackText(row, kind === 'sup' ? '^' : '_', at);
  }
  const s = newNode(kind);
  s.arg = g.node;
  row.children.push(s);
  return g.next;
}

/// 收敛：单子 row 直接降级；text 相邻合并；空 row → 空 text。
function simplify(n: LatexNode): LatexNode {
  if (n.kind === 'row' && n.children.length === 1) {
    return simplifyChild(n.children[0]);
  }
  if (n.kind === 'row') {
    // 相邻 text 合并
    const merged: LatexNode[] = [];
    for (const c of n.children) {
      const cc = simplifyChild(c);
      const last = merged.length > 0 ? merged[merged.length - 1] : null;
      if (last !== null && last.kind === 'text' && cc.kind === 'text') {
        last.text += cc.text;
      } else {
        merged.push(cc);
      }
    }
    n.children = merged;
    if (n.children.length === 1 && n.children[0].kind === 'text') {
      return n.children[0];
    }
  }
  return n;
}

function simplifyChild(c: LatexNode): LatexNode {
  if (c.kind === 'frac' || c.kind === 'sqrt' || c.kind === 'sup' || c.kind === 'sub') {
    if (c.num !== null) {
      c.num = simplify(c.num);
    }
    if (c.den !== null) {
      c.den = simplify(c.den);
    }
    if (c.arg !== null) {
      c.arg = simplify(c.arg);
    }
    return c;
  }
  if (c.kind === 'row') {
    return simplify(c);
  }
  return c;
}

/// 树 → 纯文本（嵌套兜底渲染用，也用于 \text 内容提取）。
export function flattenText(n: LatexNode): string {
  if (n.kind === 'text' || n.kind === 'sym') {
    return n.text;
  }
  if (n.kind === 'frac') {
    const a = n.num !== null ? flattenText(n.num) : '';
    const b = n.den !== null ? flattenText(n.den) : '';
    return '(' + a + ')/(' + b + ')';
  }
  if (n.kind === 'sqrt') {
    return '√(' + (n.arg !== null ? flattenText(n.arg) : '') + ')';
  }
  if (n.kind === 'sup') {
    return '^' + (n.arg !== null ? flattenText(n.arg) : '');
  }
  if (n.kind === 'sub') {
    return '_' + (n.arg !== null ? flattenText(n.arg) : '');
  }
  let out = '';
  for (const c of n.children) {
    out += flattenText(c);
  }
  return out;
}

/// 从文本中切出公式段：$$...$$（块）优先于 $...$（行内）。
/// 返回片段数组（latex 块/行内是原样源码，前后是普通文本）。
export class LatexSeg {
  latex: boolean = false;
  block: boolean = false;
  text: string = '';
}

const LATEX_SCAN: RegExp = /\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$/g;

export function splitLatex(text: string): LatexSeg[] {
  const out: LatexSeg[] = [];
  if (text.indexOf('$') < 0) {
    const s = new LatexSeg();
    s.text = text;
    if (text.length > 0) {
      out.push(s);
    }
    return out;
  }
  let last = 0;
  LATEX_SCAN.lastIndex = 0;
  let m = LATEX_SCAN.exec(text);
  while (m !== null) {
    if (m.index > last) {
      const s = new LatexSeg();
      s.text = text.substring(last, m.index);
      out.push(s);
    }
    const s = new LatexSeg();
    s.latex = true;
    s.block = m[1] !== undefined;
    s.text = (m[1] !== undefined ? m[1] : m[2]).trim();
    if (s.text.length > 0) {
      out.push(s);
    }
    last = m.index + m[0].length;
    m = LATEX_SCAN.exec(text);
  }
  if (last < text.length) {
    const s = new LatexSeg();
    s.text = text.substring(last);
    out.push(s);
  }
  return out;
}
