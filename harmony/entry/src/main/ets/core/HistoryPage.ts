/**
 * 历史事件装配模型 —— 移植自 app/lib/bridge/history_page.dart（390 行）。
 *
 * 包含：SessionEvent（内核历史事件透传）/ DeliverableFile（文件卡）/
 * ChatMessage（聊天 UI 消息）/ HistoryPage（历史响应 + fromEvents 装配器）。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { ContentImageRef, ContentParts } from './Content';
import { RawToolCall, ToolCallInfo, extractToolCalls, toolResultText, toolPhrases, toolSummary } from './ToolCall';

/** 内核历史事件（原样透传）：{type, seq, time, data}。 */
export class SessionEvent {
  type: string = '';
  seq: number = 0;
  time: number = 0; // epoch ms
  data: JsonMap = {};

  static fromJson(j: JsonMap | null): SessionEvent {
    const ev: SessionEvent = new SessionEvent();
    if (j === null) {
      return ev;
    }
    ev.type = JsonAccess.strOr(j, 'type', '');
    const seq: number | null = JsonAccess.num(j, 'seq');
    ev.seq = seq === null ? 0 : seq;
    const time: number | null = JsonAccess.num(j, 'time');
    ev.time = time === null ? 0 : time;
    ev.data = JsonAccess.obj(j, 'data') ?? {};
    return ev;
  }

  /** 归一化原始事件（剥掉 REST 外包装后），轨迹 Sheet 分组用。 */
  toRaw(): JsonMap {
    const out: JsonMap = {};
    out['type'] = this.type;
    out['seq'] = this.seq;
    out['time'] = this.time;
    out['data'] = this.data;
    return out;
  }
}

/** 文件卡：`deliverables/presented` 事件的 files 项（path/description 原样透传）。 */
export class DeliverableFile {
  readonly path: string;
  readonly description: string | null;

  constructor(path: string, description: string | null) {
    this.path = path;
    this.description = description;
  }

  static fromJson(j: JsonMap | null): DeliverableFile {
    if (j === null) {
      return new DeliverableFile('', null);
    }
    return new DeliverableFile(JsonAccess.strOr(j, 'path', ''),
      JsonAccess.str(j, 'description'));
  }

  /** 文件名（路径最后一段），UI 主标题。 */
  get name(): string {
    const parts: string[] = this.path.split('/');
    return parts[parts.length - 1];
  }
}

/** 聊天 UI 消息（由历史事件或实时流装配）。 */
export class ChatMessage {
  role: string = ''; // 'user' | 'assistant' | 'process' | 'error' | 'files' | 'command'
  text: string = '';
  reasoning: string = '';
  /** content 里的图片引用（历史形状：attachment 引用，无字节）。 */
  images: ContentImageRef[] = [];
  /** role == 'files' 时：本组交付文件。 */
  files: DeliverableFile[] = [];
  seq: number = -1; // -1 = 尚未 committed（流式中的临时消息）
  streaming: boolean = false;
  /** role == 'process' 时：本组内的工具调用（按时间顺序）。 */
  toolCalls: ToolCallInfo[] = [];
  /** 过程组的墙钟起止（epoch ms，可能缺一端）。 */
  startedAt: number | null = null;
  finishedAt: number | null = null;

  get isUser(): boolean {
    return this.role === 'user';
  }

  get isProcess(): boolean {
    return this.role === 'process';
  }

  get isError(): boolean {
    return this.role === 'error';
  }

  /** 组头耗时（毫秒）；两端齐全且为正才算（时钟倒退/同毫秒不算）。 */
  get durationMs(): number | null {
    const s: number | null = this.startedAt;
    const e: number | null = this.finishedAt;
    if (s === null || e === null) {
      return null;
    }
    const span: number = e - s;
    return span > 0 ? span : null;
  }

  /** 组头短语：去重后按出现顺序取前三个，用「，」连接。 */
  get phraseText(): string {
    const out: string[] = [];
    for (const t of this.toolCalls) {
      for (const p of t.phrases) {
        if (out.indexOf(p) < 0) {
          out.push(p);
        }
      }
    }
    if (out.length === 0) {
      return '思考中';
    }
    const head: string = out.slice(0, 3).join('，');
    return out.length > 3 ? head + ' 等' : head;
  }
}

/** 历史响应（REST 与 WS history 同源）：{items, hasMore, rawEvents, projections?}。 */
export class HistoryPage {
  /** 已装配为 UI 消息（user/assistant/process；tool/turn 等装配进 process）。 */
  items: ChatMessage[] = [];
  hasMore: boolean = false;
  /** 原始事件（已剥掉 REST `{event:...}` 外包装），轨迹 Sheet 用。 */
  rawEvents: JsonMap[] = [];
  /**
   * 服务端算好的投影（团队/TODO/权限/token 等）。**可选**：内核没给基线时整个
   * 字段缺席（不是空对象），且只在 history 首屏应答带、翻页不带
   * （bridge docs/project/API.md:165,766）。UI 必须容忍 null/缺席，不能把
   * 「读不到投影」当成「没有这个功能」（v2.2.44 真机踩过）。
   */
  projections: JsonMap | null = null;

  /**
   * 从 REST events / WS history 的 events 数组装配。
   *
   * content 位置实测（bridge v2.10 内核透传）：user/message 在 data.content，
   * assistant/message 在 data.message.content（turn/step/message 包裹）——两处都兜底。
   *
   * 分组规则（对齐官方 App 观感）：
   * 1. 一条 assistant/message 里只有 reasoning/tool-call、没有正文 → 不算消息，
   *    把它的工具调用塞进「当前过程组」（否则连续工具调用会被零高度空消息劈成几十段）；
   * 2. 相邻的 tool/call + tool/result 按 callId 合并进同一个过程组；
   * 3. 出现真正有正文的 assistant 消息时，先把当前过程组 flush 掉，再追加正文消息；
   * 4. 过程组内只有 1 次工具调用时照样产出一组，折不折由 UI 决定。
   */
  static fromEvents(rawEvents: Object[], projections: JsonMap | null,
                    hasMore: boolean): HistoryPage {
    const page: HistoryPage = new HistoryPage();
    const items: ChatMessage[] = [];
    const normalized: JsonMap[] = [];

    // 当前过程组的累积缓冲。
    const groupCalls: ToolCallInfo[] = [];
    const pending: Map<string, RawToolCall> = new Map(); // callId → 调用信息（等 result 补全）
    let groupStart: number | null = null;
    let groupEnd: number | null = null;

    // 文件卡暂存：内核在 present 工具 result 成功的**当场**追加
    // deliverables/presented（seq 落在收尾正文之前）——按事件序内联插卡会卡在
    // 工具过程与收尾回复之间。官方 Web 端把 deliverables 当轮次局部累积器，
    // 卡片挂在 turn-tail（收尾回复之后）；这里同样延迟到轮尾再上屏。
    // 轮尾判定：下一条 user/message（新一轮开始）、turn/end、或事件流末尾。
    const pendingFileCards: ChatMessage[] = [];

    const flushGroup = (): void => {
      if (groupCalls.length === 0) {
        return;
      }
      const msg: ChatMessage = new ChatMessage();
      msg.role = 'process';
      msg.text = '';
      msg.seq = -1;
      msg.toolCalls = groupCalls.slice(); // 拷贝：缓冲复用（安卓 List.unmodifiable 同口径）
      msg.startedAt = groupStart;
      msg.finishedAt = groupEnd;
      items.push(msg);
      groupCalls.length = 0;
      pending.clear();
      groupStart = null;
      groupEnd = null;
    };

    const flushFileCards = (): void => {
      flushGroup(); // 先收口未闭合的过程组（轮尾的工具调用排在卡前）
      if (pendingFileCards.length === 0) {
        return;
      }
      for (const m of pendingFileCards) {
        items.push(m);
      }
      pendingFileCards.length = 0;
    };

    for (const e of rawEvents) {
      // REST 返回 {event:{...}} 包装；WS history 同构。容错：直接给事件体也收。
      const outer: JsonMap | null = JsonAccess.asMap(e);
      if (outer === null) {
        continue;
      }
      const ev: SessionEvent = SessionEvent.fromJson(
        JsonAccess.obj(outer, 'event') ?? outer);
      normalized.push(ev.toRaw());

      // content 位置双兜底：data.message.content（assistant）或 data.content（user）。
      let content: Object | null = null;
      const inner: JsonMap | null = JsonAccess.obj(ev.data, 'message');
      if (inner !== null && JsonAccess.raw(inner, 'content') !== null) {
        content = JsonAccess.raw(inner, 'content');
      } else {
        content = JsonAccess.raw(ev.data, 'content');
      }

      switch (ev.type) {
        case 'user/message': {
          // 只显示真实用户输入。DSH 会把 runtime-context / skill-catalog /
          // time-context 等注入内容也记成 user/message（data.source.kind 区分），
          // 官方 App 一律不显示 —— 我们也过滤掉，否则每条回复前都被巨长上下文淹没。
          const src: JsonMap | null = JsonAccess.obj(ev.data, 'source');
          const kind: string | null = src === null ? null : JsonAccess.str(src, 'kind');
          if (kind !== null && kind !== 'user') {
            break;
          }
          const parts: ContentParts = ContentParts.from(content);
          // 纯图无文字也要上屏（真机反馈 2026-11-04 第 1 项）。
          if (parts.text !== '' || parts.images.length > 0) {
            // 新一轮开始：上一轮的文件卡挂尾（本轮之后、这条用户消息之前）。
            flushFileCards();
            const msg: ChatMessage = new ChatMessage();
            msg.role = 'user';
            msg.text = parts.text;
            msg.images = parts.images;
            msg.seq = ev.seq;
            items.push(msg);
          }
          break;
        }

        case 'assistant/message': {
          // 一条 assistant/message 可能同时含正文与工具调用（content 数组混排）。
          const parts: ContentParts = ContentParts.from(content);
          const calls: RawToolCall[] = extractToolCalls(content);
          if (parts.text === '' && parts.reasoning === '' && calls.length === 0) {
            break;
          }
          if (parts.text === '') {
            // 没有正文：这是「过程」，不进消息流。工具调用进当前过程组。
            // 去重：内核对同一次调用会发两遍 —— 内嵌在 assistant/message
            // content 里（type=tool-call）+ 独立 tool/call 事件。以独立事件为准，
            // 这里只记「有调用发生」，明细等 tool/call 事件补全。
            for (const c of calls) {
              pending.set(c.callId, c);
              let dup: boolean = false;
              for (const g of groupCalls) {
                if (g.callId === c.callId) {
                  dup = true;
                  break;
                }
              }
              if (!dup) {
                groupCalls.push(c.toInfo());
              }
              if (groupStart === null) {
                groupStart = ev.time;
              }
              groupEnd = ev.time;
            }
            break;
          }
          flushGroup();
          const msg: ChatMessage = new ChatMessage();
          msg.role = 'assistant';
          msg.text = parts.text;
          msg.reasoning = parts.reasoning;
          msg.seq = ev.seq;
          items.push(msg);
          break;
        }

        case 'tool/call': {
          const callId: string = JsonAccess.strOr(ev.data, 'callId', '');
          if (callId === '') {
            break;
          }
          const raw: RawToolCall = new RawToolCall();
          raw.callId = callId;
          raw.name = JsonAccess.strOr(ev.data, 'name', '');
          raw.arguments = JsonAccess.str(ev.data, 'arguments');
          raw.time = ev.time;
          pending.set(callId, raw);
          // 同一 callId 可能已被 assistant/message 内嵌块登记过 → 就地升级明细，
          // 不重复追加（否则展开后会看到两条一模一样的调用）。
          let dupIdx: number = -1;
          for (let i = 0; i < groupCalls.length; i++) {
            if (groupCalls[i].callId === callId) {
              dupIdx = i;
              break;
            }
          }
          if (dupIdx >= 0) {
            groupCalls[dupIdx] = raw.toInfo();
          } else {
            groupCalls.push(raw.toInfo());
          }
          if (groupStart === null) {
            groupStart = ev.time;
          }
          groupEnd = ev.time;
          break;
        }

        case 'tool/result': {
          const msg: JsonMap | null = JsonAccess.obj(ev.data, 'message');
          if (msg === null) {
            break;
          }
          let callId: string = JsonAccess.str(msg, 'toolCallId');
          if (callId === '') {
            const src: JsonMap | null = JsonAccess.obj(msg, 'source');
            callId = src === null ? '' : JsonAccess.strOr(src, 'callId', '');
          }
          if (callId === '') {
            break;
          }
          const raw: RawToolCall | undefined = pending.get(callId);
          if (raw === undefined) {
            break;
          }
          let idx: number = -1;
          for (let i = 0; i < groupCalls.length; i++) {
            if (groupCalls[i].callId === callId) {
              idx = i;
              break;
            }
          }
          if (idx < 0) {
            break;
          }
          const failed: boolean = JsonAccess.boolOr(msg, 'isError', false);
          raw.failed = failed;
          raw.resultText = toolResultText(JsonAccess.raw(msg, 'content'));
          const info: ToolCallInfo = new ToolCallInfo(callId, raw.name,
            toolPhrases(raw.name, raw.arguments), toolSummary(raw.arguments),
            failed,
            ev.time - raw.time > 0 ? ev.time - raw.time : null,
            raw.resultText, raw.arguments);
          groupCalls[idx] = info;
          groupEnd = ev.time;
          break;
        }

        case 'deliverables/presented': {
          // 文件卡：内核 present 工具交付的文件。files 原样透传
          // [{path, description}]；连续多个事件不合并，一事件一卡组。
          // 落位：不按事件序内联，先暂存，挂到本轮流尾（收尾回复之后）。
          const rawFiles: Object[] = JsonAccess.arr(ev.data, 'files');
          if (rawFiles.length === 0) {
            break;
          }
          const files: DeliverableFile[] = [];
          for (const f of rawFiles) {
            const fm: JsonMap | null = JsonAccess.asMap(f);
            if (fm === null) {
              continue;
            }
            const df: DeliverableFile = DeliverableFile.fromJson(fm);
            if (df.path !== '') {
              files.push(df);
            }
          }
          if (files.length === 0) {
            break;
          }
          const card: ChatMessage = new ChatMessage();
          card.role = 'files';
          card.files = files;
          card.seq = ev.seq;
          card.startedAt = ev.time;
          pendingFileCards.push(card);
          break;
        }

        case 'turn/end': {
          // 本轮到此结束（正常/失败都算）：文件卡挂在本轮流尾 —— 两轮之间
          // 未必有 user/message（目标续跑、子任务回合），turn/end 是唯一
          // 稳定的轮边界，必须在这里收口。
          flushFileCards();
          // 一轮 turn 失败（模型限流/额度耗尽）：内核只在 turn/end 的 reason
          // 里给结论，没有 assistant/message 正文 —— 不解析就会表现成「用户发完
          // 消息、界面什么都没有」。官方 App 是红色错误提示，用同一套
          // role=error 消息渲染。
          const reason: JsonMap | null = JsonAccess.obj(ev.data, 'reason');
          if (reason === null || JsonAccess.strOr(reason, 'kind', '') !== 'error') {
            break;
          }
          const err: JsonMap | null = JsonAccess.obj(reason, 'error');
          const errMsg: string = err === null ? '' : JsonAccess.strOr(err, 'message', '');
          if (errMsg === '') {
            break;
          }
          const msg: ChatMessage = new ChatMessage();
          msg.role = 'error';
          msg.text = errMsg;
          msg.seq = ev.seq;
          items.push(msg);
          break;
        }

        default:
          break;
      }
    }
    // 事件流末尾：最后一轮的文件卡挂尾。
    flushFileCards();
    page.items = items;
    // hasMore 由调用方从应答传入（REST openapi.yaml:944-1009 / WS history 帧都带）。
    page.hasMore = hasMore;
    page.rawEvents = normalized;
    page.projections = projections;
    return page;
  }
}
