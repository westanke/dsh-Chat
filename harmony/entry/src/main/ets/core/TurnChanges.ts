/**
 * 本轮改动 / 本轮生成文件 —— 移植自安卓 app/lib/ui/turn_changes.dart（377 行）。
 *
 * 桥没有 workspace-changes 查询面，`workspace/changes` 事件只带 `{turn}`，
 * 所以客户端本地推导：edit/write 的 `tool/result.meta.diffs` 优先，拿不到
 * 退回工具参数（file_path/old_string/new_string/content）。
 *
 * 数据形状（桥原样透传）：
 * - edit：meta `{path, diffs:[{path, oldText, newText}]}`
 * - write：meta `{operation:'create'|'update', path, diffs}`
 * - bash：meta `{cwd}` —— 给生成文件的相对路径当基准目录。
 *
 * 纯逻辑，不 import 任何 @kit，node 直测。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { ChatMessage } from './HistoryPage';
import { ToolCallInfo } from './ToolCall';
import { DIFF_LINE_ADD, DIFF_LINE_DEL, DiffLine, diffLinesOf } from './CodeDiff';

/** 一次编辑（一次工具调用里的一个 diff 项）。 */
export class EditHunk {
  /** 该文件在本轮里的第几次修改（1 起）。 */
  index: number = 0;
  lines: DiffLine[] = [];

  constructor(index: number, lines: DiffLine[]) {
    this.index = index;
    this.lines = lines;
  }
}

/** 本轮里被改的一个文件。 */
export class FileChange {
  /** 绝对路径（工具参数就是绝对路径）。 */
  path: string = '';
  /** 本轮新建（write create / 首次 write 且此前不存在）。 */
  created: boolean = false;
  hunks: EditHunk[] = [];
  added: number = 0;
  removed: number = 0;

  /** 文件名。 */
  name(): string {
    return fileNameOf(this.path);
  }

  /** 目录（卡片第二行弱化显示，超长由 Text ellipsis 截断）。 */
  directory(): string {
    return dirNameOf(this.path);
  }

  /** 改了几次（= 几个 diff 项）。 */
  edits(): number {
    return this.hunks.length;
  }
}

/** 本轮全部改动。 */
export class TurnChanges {
  /** 该轮首条消息的 seq（行 key 用，稳定）。 */
  anchorSeq: number = 0;
  files: FileChange[] = [];

  constructor(anchorSeq: number, files: FileChange[]) {
    this.anchorSeq = anchorSeq;
    this.files = files;
  }

  isEmpty(): boolean {
    return this.files.length === 0;
  }

  added(): number {
    let sum: number = 0;
    for (let i = 0; i < this.files.length; i++) {
      sum += this.files[i].added;
    }
    return sum;
  }

  removed(): number {
    let sum: number = 0;
    for (let i = 0; i < this.files.length; i++) {
      sum += this.files[i].removed;
    }
    return sum;
  }
}

class FileBuilder {
  created: boolean = false;
  added: number = 0;
  removed: number = 0;
  hunks: EditHunk[] = [];
}

/** 路径最后一段（文件名）。 */
export function fileNameOf(path: string): string {
  const i: number = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/** 路径去掉最后一段（目录）；根目录/单段路径返回空串。 */
export function dirNameOf(path: string): string {
  const i: number = path.lastIndexOf('/');
  return i <= 0 ? '' : path.substring(0, i);
}

/**
 * 本轮改动；没有改动返回 null。
 *
 * 只算**已完成**的轮（调用方不传正在跑的那轮）：工具结果没到齐时计数会跳。
 * `start`/`end` 是该轮在 messages 里的区间（[start,end)），由 WorkSteps 的
 * turnRangesOf 提供。
 */
export function turnChangesOf(messages: ChatMessage[], start: number, end: number): TurnChanges | null {
  if (start < 0 || end > messages.length || start >= end) {
    return null;
  }
  const anchorSeq: number = messages[start].seq;
  const calls: ToolCallInfo[] = [];
  for (let i = start + 1; i < end; i++) {
    const message: ChatMessage = messages[i];
    if (!message.isProcess) {
      continue;
    }
    for (let c = 0; c < message.toolCalls.length; c++) {
      const call: ToolCallInfo = message.toolCalls[c];
      if (!call.failed) {
        calls.push(call);
      }
    }
  }
  return computeChanges(anchorSeq, calls);
}

function computeChanges(anchorSeq: number, calls: ToolCallInfo[]): TurnChanges | null {
  const order: string[] = [];
  const byPath: Map<string, FileBuilder> = new Map<string, FileBuilder>();
  for (let i = 0; i < calls.length; i++) {
    applyCall(calls[i], order, byPath);
  }
  if (order.length === 0) {
    return null;
  }
  const files: FileChange[] = [];
  for (let i = 0; i < order.length; i++) {
    const builder: FileBuilder | undefined = byPath.get(order[i]);
    if (builder === undefined) {
      continue;
    }
    const file: FileChange = new FileChange();
    file.path = order[i];
    file.created = builder.created;
    file.hunks = builder.hunks;
    file.added = builder.added;
    file.removed = builder.removed;
    files.push(file);
  }
  return new TurnChanges(anchorSeq, files);
}

function applyCall(call: ToolCallInfo, order: string[],
                   byPath: Map<string, FileBuilder>): void {
  const name: string = bareToolName(call.name);
  if (name !== 'edit' && name !== 'write') {
    return;
  }
  const meta: JsonMap | null = call.meta;
  const operation: string = meta === null ? '' : JsonAccess.strOr(meta, 'operation', '');
  const diffs: JsonMap[] = meta === null ? [] : JsonAccess.objArr(meta, 'diffs');
  if (diffs.length > 0) {
    for (let i = 0; i < diffs.length; i++) {
      const raw: JsonMap = diffs[i];
      const path: string = JsonAccess.strOr(raw, 'path', '');
      const newText: string | null = JsonAccess.str(raw, 'newText');
      if (path === '' || newText === null) {
        continue;
      }
      const oldText: string = JsonAccess.strOr(raw, 'oldText', '');
      addHunk(order, byPath, path, oldText, newText,
        operation === 'create' || (name === 'write' && oldText === ''));
    }
    return;
  }
  const args: JsonMap | null = decodeArgs(call.rawArguments);
  if (args === null) {
    return;
  }
  let path: string = JsonAccess.strOr(args, 'file_path', '');
  if (path === '') {
    path = JsonAccess.strOr(args, 'path', '');
  }
  if (path === '') {
    return;
  }
  if (name === 'edit') {
    let oldText: string | null = JsonAccess.str(args, 'old_string');
    if (oldText === null) {
      oldText = JsonAccess.str(args, 'oldText');
    }
    let newText: string | null = JsonAccess.str(args, 'new_string');
    if (newText === null) {
      newText = JsonAccess.str(args, 'newText');
    }
    if (newText === null) {
      return;
    }
    addHunk(order, byPath, path, oldText === null ? '' : oldText, newText,
      oldText === null || oldText === '');
    return;
  }
  const content: string | null = JsonAccess.str(args, 'content');
  if (content === null) {
    return;
  }
  addHunk(order, byPath, path, '', content, operation !== 'update');
}

function addHunk(order: string[], byPath: Map<string, FileBuilder>,
                 path: string, oldText: string, newText: string, created: boolean): void {
  let builder: FileBuilder | undefined = byPath.get(path);
  if (builder === undefined) {
    builder = new FileBuilder();
    byPath.set(path, builder);
    order.push(path);
  }
  if (created) {
    builder.created = true;
  }
  const lines: DiffLine[] = diffLinesOf(oldText, newText);
  let added: number = 0;
  let removed: number = 0;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].type === DIFF_LINE_ADD) {
      added += 1;
    } else if (lines[i].type === DIFF_LINE_DEL) {
      removed += 1;
    }
  }
  builder.hunks.push(new EditHunk(builder.hunks.length + 1, lines));
  builder.added += added;
  builder.removed += removed;
}

// ---------- 本轮生成的文件 ----------

/** 文件类型（决定图标与「图片 · PNG」这类说明文字）。 */
export const ARTIFACT_IMAGE: string = 'image';
export const ARTIFACT_PDF: string = 'pdf';
export const ARTIFACT_DOCUMENT: string = 'document';
export const ARTIFACT_SPREADSHEET: string = 'spreadsheet';
export const ARTIFACT_SLIDES: string = 'slides';
export const ARTIFACT_ARCHIVE: string = 'archive';
export const ARTIFACT_AUDIO: string = 'audio';
export const ARTIFACT_VIDEO: string = 'video';
export const ARTIFACT_WEB: string = 'web';
export const ARTIFACT_MARKDOWN: string = 'markdown';
export const ARTIFACT_TEXT: string = 'text';
export const ARTIFACT_OTHER: string = 'other';

/** 类型中文名（卡片的「图片 · PNG」）。 */
export function artifactKindLabel(kind: string): string {
  if (kind === ARTIFACT_IMAGE) {
    return '图片';
  }
  if (kind === ARTIFACT_PDF) {
    return 'PDF';
  }
  if (kind === ARTIFACT_DOCUMENT) {
    return '文档';
  }
  if (kind === ARTIFACT_SPREADSHEET) {
    return '表格';
  }
  if (kind === ARTIFACT_SLIDES) {
    return '幻灯片';
  }
  if (kind === ARTIFACT_ARCHIVE) {
    return '压缩包';
  }
  if (kind === ARTIFACT_AUDIO) {
    return '音频';
  }
  if (kind === ARTIFACT_VIDEO) {
    return '视频';
  }
  if (kind === ARTIFACT_WEB) {
    return '网页';
  }
  if (kind === ARTIFACT_MARKDOWN) {
    return 'Markdown';
  }
  if (kind === ARTIFACT_TEXT) {
    return '文本';
  }
  return '文件';
}

/** 本轮生成的一个文件。 */
export class ArtifactFile {
  path: string = '';
  kind: string = ARTIFACT_OTHER;

  constructor(path: string, kind: string) {
    this.path = path;
    this.kind = kind;
  }

  name(): string {
    return fileNameOf(this.path);
  }

  /** 「图片 · PNG」。 */
  caption(): string {
    const i: number = this.path.lastIndexOf('.');
    const ext: string = i < 0 ? '' : this.path.substring(i + 1).toUpperCase();
    const label: string = artifactKindLabel(this.kind);
    return ext === '' ? label : label + ' · ' + ext;
  }
}

/**
 * 本轮生成的文件：本轮 write 新建的文件 + 本轮最终回复里引用的图片/文件链接。
 *
 * 已 `present` 交付的文件不在这里（那由 role=='files' 的交付卡渲染）。
 */
export function turnArtifactsOf(messages: ChatMessage[], start: number, end: number): ArtifactFile[] {
  if (start < 0 || end > messages.length || start >= end) {
    return [];
  }
  const paths: string[] = [];
  const seen: Set<string> = new Set<string>();
  let base: string = '';
  for (let i = start + 1; i < end; i++) {
    const message: ChatMessage = messages[i];
    if (message.isProcess) {
      for (let c = 0; c < message.toolCalls.length; c++) {
        const call: ToolCallInfo = message.toolCalls[c];
        if (call.failed) {
          continue;
        }
        const cwd: string = call.meta === null ? '' : JsonAccess.strOr(call.meta, 'cwd', '');
        if (cwd !== '') {
          base = cwd;
        }
        if (bareToolName(call.name) !== 'write') {
          continue;
        }
        const args: JsonMap | null = decodeArgs(call.rawArguments);
        if (args === null) {
          continue;
        }
        let path: string = JsonAccess.strOr(args, 'file_path', '');
        if (path === '') {
          path = JsonAccess.strOr(args, 'path', '');
        }
        if (path === '') {
          continue;
        }
        const op: string = call.meta === null ? '' : JsonAccess.strOr(call.meta, 'operation', '');
        if (op === 'update') {
          continue;
        }
        if (!seen.has(path)) {
          seen.add(path);
          paths.push(path);
        }
      }
      continue;
    }
    if (message.isUser) {
      continue;
    }
    const refs: string[] = markdownRefs(message.text);
    for (let r = 0; r < refs.length; r++) {
      const resolved: string | null = resolveRef(refs[r], base);
      if (resolved === null) {
        continue;
      }
      if (!seen.has(resolved)) {
        seen.add(resolved);
        paths.push(resolved);
      }
    }
  }
  const out: ArtifactFile[] = [];
  for (let i = 0; i < paths.length; i++) {
    out.push(new ArtifactFile(paths[i], artifactKindOf(paths[i])));
  }
  return out;
}

/** 工具名去掉 `tools.` 前缀（run_code 内嵌调用）。 */
export function bareToolName(name: string): string {
  return name.startsWith('tools.') ? name.substring(6) : name;
}

/** 扩展名 → 类型。 */
export function artifactKindOf(path: string): string {
  const dot: number = path.lastIndexOf('.');
  if (dot < 0 || dot === path.length - 1) {
    return ARTIFACT_OTHER;
  }
  const ext: string = path.substring(dot + 1).toLowerCase();
  if (ext === 'png' || ext === 'jpg' || ext === 'jpeg' || ext === 'gif'
    || ext === 'webp' || ext === 'bmp' || ext === 'svg' || ext === 'heic') {
    return ARTIFACT_IMAGE;
  }
  if (ext === 'pdf') {
    return ARTIFACT_PDF;
  }
  if (ext === 'doc' || ext === 'docx' || ext === 'rtf' || ext === 'odt') {
    return ARTIFACT_DOCUMENT;
  }
  if (ext === 'xls' || ext === 'xlsx' || ext === 'csv' || ext === 'ods') {
    return ARTIFACT_SPREADSHEET;
  }
  if (ext === 'ppt' || ext === 'pptx' || ext === 'odp' || ext === 'key') {
    return ARTIFACT_SLIDES;
  }
  if (ext === 'zip' || ext === 'tar' || ext === 'gz' || ext === 'tgz'
    || ext === '7z' || ext === 'rar' || ext === 'xz') {
    return ARTIFACT_ARCHIVE;
  }
  if (ext === 'mp3' || ext === 'wav' || ext === 'm4a' || ext === 'flac'
    || ext === 'ogg' || ext === 'aac') {
    return ARTIFACT_AUDIO;
  }
  if (ext === 'mp4' || ext === 'mov' || ext === 'mkv' || ext === 'webm' || ext === 'avi') {
    return ARTIFACT_VIDEO;
  }
  if (ext === 'html' || ext === 'htm') {
    return ARTIFACT_WEB;
  }
  if (ext === 'md' || ext === 'markdown') {
    return ARTIFACT_MARKDOWN;
  }
  if (ext === 'txt' || ext === 'log' || ext === 'json' || ext === 'yaml'
    || ext === 'yml' || ext === 'xml' || ext === 'toml' || ext === 'dart'
    || ext === 'ts' || ext === 'js' || ext === 'py' || ext === 'sh') {
    return ARTIFACT_TEXT;
  }
  return ARTIFACT_OTHER;
}

/** 回复里的图片 / 文件引用：`![alt](path)` 与 `[text](path)` 的本地路径。 */
export function markdownRefs(text: string): string[] {
  const out: string[] = [];
  if (text === '') {
    return out;
  }
  const pattern: RegExp = new RegExp('!?\\[[^\\]]*\\]\\(([^)\\s]+)\\)', 'g');
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null) {
    const target: string = match[1];
    if (target !== '' && !target.startsWith('http://') && !target.startsWith('https://')
      && !target.startsWith('data:') && !target.startsWith('#')) {
      out.push(target);
    }
    match = pattern.exec(text);
  }
  return out;
}

/**
 * 相对路径按本轮最后的 bash cwd 拼绝对路径；拼不出来返回 null
 * （缩略图取不到，卡片就不该列一个点不开的路径）。
 */
export function resolveRef(ref: string, base: string): string | null {
  if (ref.startsWith('/')) {
    return ref;
  }
  if (base === '') {
    return null;
  }
  const trimmedBase: string = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return trimmedBase + '/' + ref;
}

/** 工具参数 JSON → Map（坏参数返回 null，不抛）。 */
export function decodeArgs(raw: string | null): JsonMap | null {
  if (raw === null || raw.trim() === '') {
    return null;
  }
  return JsonAccess.asMap(JsonAccess.parse(raw));
}
