/// 代码块轻量语法高亮（纯逻辑，node 直测）。
/// 安卓用 val_highlight + Atom One Light；鸿蒙生态无等价物，自写逐行 tokenizer：
/// 关键词 / 字符串 / 注释 / 数字 四类着色，色值走 theme.ets 的 Atom One Light 对照
/// （kw #a626a4 / str #50a14f / num #4078f2 / comment #a0a1a7 / plain #383a42）。
/// 首版口径：逐行独立（多行字符串/块注释不跨行），未知语言全 plain。
/// ArkTS 口径：扁平 class，无 any。
export class HlSpan {
  text: string = '';
  cls: string = 'plain'; // plain | str | num | comment | kw
}

const PY_KW: string[] = ['def', 'class', 'import', 'from', 'as', 'return', 'if', 'elif',
  'else', 'for', 'while', 'break', 'continue', 'pass', 'in', 'is', 'not', 'and', 'or',
  'None', 'True', 'False', 'try', 'except', 'finally', 'raise', 'with', 'yield', 'lambda',
  'global', 'nonlocal', 'assert', 'async', 'await', 'del', 'match', 'case',
  'print', 'self', 'len', 'range', 'str', 'int', 'float', 'list', 'dict', 'set',
  'open', 'super', 'type', 'isinstance', 'enumerate', 'zip', 'map', 'filter'];

const BASH_KW: string[] = ['if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done',
  'case', 'esac', 'function', 'return', 'export', 'local', 'echo', 'read', 'exit',
  'ls', 'cd', 'mkdir', 'rm', 'cp', 'mv', 'touch', 'chmod', 'chown', 'cat', 'grep',
  'sed', 'awk', 'curl', 'wget', 'git', 'npm', 'node', 'python', 'pip', 'sudo', 'apt',
  'tar', 'unzip', 'ssh', 'scp', 'sleep', 'kill', 'source', 'set', 'true', 'false'];

const JS_KW: string[] = ['function', 'return', 'if', 'else', 'for', 'while', 'do', 'break',
  'continue', 'const', 'let', 'var', 'class', 'extends', 'new', 'this', 'super', 'import',
  'export', 'from', 'default', 'async', 'await', 'try', 'catch', 'finally', 'throw',
  'typeof', 'instanceof', 'in', 'of', 'null', 'undefined', 'true', 'false', 'switch',
  'case', 'delete', 'void', 'yield', 'static', 'get', 'set'];

const GO_KW: string[] = ['func', 'package', 'import', 'return', 'if', 'else', 'for', 'range',
  'go', 'defer', 'chan', 'select', 'switch', 'case', 'default', 'type', 'struct', 'interface',
  'map', 'nil', 'true', 'false', 'var', 'const', 'break', 'continue', 'goto'];

const SQL_KW: string[] = ['SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE',
  'SET', 'DELETE', 'CREATE', 'TABLE', 'ALTER', 'DROP', 'JOIN', 'LEFT', 'RIGHT', 'INNER',
  'OUTER', 'ON', 'GROUP', 'BY', 'ORDER', 'LIMIT', 'HAVING', 'AS', 'AND', 'OR', 'NOT',
  'NULL', 'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES', 'UNION', 'DISTINCT', 'COUNT',
  'SUM', 'AVG', 'MIN', 'MAX'];

const LANG_KW: Map<string, string[]> = new Map<string, string[]>([
  ['python', PY_KW], ['python3', PY_KW], ['py', PY_KW],
  ['javascript', JS_KW], ['js', JS_KW], ['typescript', JS_KW], ['ts', JS_KW],
  ['node', JS_KW], ['nodejs', JS_KW], ['json', JS_KW], ['java', JS_KW],
  ['kotlin', JS_KW], ['kt', JS_KW], ['swift', JS_KW], ['c', JS_KW], ['cpp', JS_KW],
  ['c++', JS_KW], ['cs', JS_KW], ['csharp', JS_KW], ['dart', JS_KW], ['php', JS_KW],
  ['rust', JS_KW], ['rs', JS_KW], ['scala', JS_KW], ['go', GO_KW], ['golang', GO_KW],
  ['sql', SQL_KW], ['mysql', SQL_KW], ['sqlite', SQL_KW],
  ['bash', BASH_KW], ['sh', BASH_KW], ['shell', BASH_KW], ['shellscript', BASH_KW],
]);

const LINE_COMMENT: Map<string, string> = new Map<string, string>([
  ['python', '#'], ['python3', '#'], ['py', '#'], ['bash', '#'], ['sh', '#'],
  ['shell', '#'], ['shellscript', '#'], ['yaml', '#'], ['yml', '#'], ['ruby', '#'],
  ['r', '#'], ['perl', '#'], ['ini', '#'], ['toml', '#'],
  ['js', '//'], ['javascript', '//'], ['ts', '//'], ['typescript', '//'],
  ['java', '//'], ['kotlin', '//'], ['kt', '//'], ['swift', '//'], ['c', '//'],
  ['cpp', '//'], ['c++', '//'], ['cs', '//'], ['csharp', '//'], ['go', '//'],
  ['golang', '//'], ['dart', '//'], ['rust', '//'], ['rs', '//'], ['php', '//'],
  ['sql', '--'], ['mysql', '--'], ['sqlite', '--'], ['lua', '--'], ['haskell', '--'],
]);

/// 高亮一段代码（逐行独立）。未知语言/空标签 → 全 plain。
export function highlight(code: string, lang: string): HlSpan[][] {
  const tag = lang.trim().toLowerCase();
  if (tag.length === 0) {
    return plainAll(code);
  }
  const kw = LANG_KW.get(tag);
  const comment = LINE_COMMENT.get(tag);
  if (kw === undefined || comment === undefined) {
    return plainAll(code);
  }
  const out: HlSpan[][] = [];
  const lines = code.split('\n');
  for (const line of lines) {
    out.push(highlightLine(line, kw, comment));
  }
  return out;
}

function plainAll(code: string): HlSpan[][] {
  const out: HlSpan[][] = [];
  const lines = code.split('\n');
  for (const line of lines) {
    const spans: HlSpan[] = [];
    if (line.length > 0) {
      const s = new HlSpan();
      s.text = line;
      spans.push(s);
    }
    out.push(spans);
  }
  return out;
}

const RE_TOKEN: RegExp = /("[^"\n]*"|'[^'\n]*'|`[^`\n]*`)|(\b\d+(?:\.\d+)?\b)/g;

/// 单行 tokenizer：先切注释，再扫字符串/数字，余下按词边界比对关键词。
function highlightLine(line: string, kw: string[], comment: string): HlSpan[] {
  const spans: HlSpan[] = [];
  // 1. 行注释（必须在字符串之外才生效——简化：先找最早的注释符且不在字符串内）
  const cIdx = commentIndex(line, comment);
  let codePart = line;
  let commentPart = '';
  if (cIdx >= 0) {
    codePart = line.substring(0, cIdx);
    commentPart = line.substring(cIdx);
  }
  // 2. 扫 codePart：字符串段整段 str，数字段 num，词边界比对 kw
  let last = 0;
  RE_TOKEN.lastIndex = 0;
  let m = RE_TOKEN.exec(codePart);
  while (m !== null) {
    if (m.index > last) {
      pushPlainWords(spans, codePart.substring(last, m.index), kw);
    }
    if (m[1] !== undefined) {
      const s = new HlSpan();
      s.text = m[1];
      s.cls = 'str';
      spans.push(s);
    } else if (m[2] !== undefined) {
      const s = new HlSpan();
      s.text = m[2];
      s.cls = 'num';
      spans.push(s);
    }
    last = m.index + m[0].length;
    m = RE_TOKEN.exec(codePart);
  }
  if (last < codePart.length) {
    pushPlainWords(spans, codePart.substring(last), kw);
  }
  // 3. 注释段
  if (commentPart.length > 0) {
    const s = new HlSpan();
    s.text = commentPart;
    s.cls = 'comment';
    spans.push(s);
  }
  return spans;
}

/// 注释符生效位置：不在字符串字面量内（' " ` 成对计数为偶数时才算）。
function commentIndex(line: string, comment: string): number {
  let quote: string = '';
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quote.length > 0) {
      if (ch === quote) {
        quote = '';
      }
      continue;
    }
    if (ch === '\'' || ch === '"' || ch === '`') {
      quote = ch;
      continue;
    }
    if (line.startsWith(comment, i)) {
      return i;
    }
  }
  return -1;
}

/// 无标记文本段：按词边界拆关键词（精确匹配；SQL 表全大写、其余表全小写）。
function pushPlainWords(spans: HlSpan[], text: string, kw: string[]): void {
  if (text.length === 0) {
    return;
  }
  const kwSet: Map<string, boolean> = new Map<string, boolean>();
  for (const k of kw) {
    kwSet.set(k, true);
  }
  let plain = '';
  let word = '';
  const flushPlain = (): void => {
    if (plain.length > 0) {
      const p = new HlSpan();
      p.text = plain;
      spans.push(p);
      plain = '';
    }
  };
  const flushWord = (): void => {
    if (word.length === 0) {
      return;
    }
    if (kwSet.get(word) === true) {
      flushPlain();
      const s = new HlSpan();
      s.text = word;
      s.cls = 'kw';
      spans.push(s);
    } else {
      plain += word;
    }
    word = '';
  };
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (/[A-Za-z0-9_]/.test(ch)) {
      if (word.length === 0) {
        flushPlain();
      }
      word += ch;
    } else {
      flushWord();
      plain += ch;
    }
  }
  flushWord();
  flushPlain();
}
