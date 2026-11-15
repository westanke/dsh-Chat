/**
 * history 应答的「本地投影」解析 —— 移植 app/lib/bridge/projections.dart。
 *
 * 对照 dsh-companion：
 * - 轨迹 = 客户端拿 history.events 自己分组（data/Trajectory.kt:98-127）；
 * - 团队 / TODO = 读服务端算好随首屏 history 下发的 projections.values.*
 *   （data/AgentTeamProjection.kt:100-151、data/ChatPresentation.kt:77-85）。
 *
 * 约束（bridge docs/project/API.md:165,167,766）：projections 可选、内核没给
 * 基线时整个字段缺席（不是空对象）、只在首屏带翻页不带。所有函数都容忍
 * null / 形状不对，返回空结构而不是抛异常；UI 不得把「读不到」当成「功能不存在」。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { ChatMessage } from './HistoryPage';

/** 未带 data.turn 的事件归到 0，时间轴里永远垫底（companion 显示「轮次之间」）。 */
export const UNKNOWN_TURN: number = 0;

export enum TrajectoryNodeKind {
  USER = 0,
  ASSISTANT = 1,
  TOOL = 2,
  DELIVERABLE = 3,
  TURN_END = 4,
  OTHER = 5,
}

export class TrajectoryNode {
  seq: number = 0;
  time: number = 0;
  kind: TrajectoryNodeKind = TrajectoryNodeKind.OTHER;
  label: string = '';
  raw: JsonMap | null = null;
  /** 原始事件类型（other 类节点用它做标签，不臆造）。 */
  type: string = '';
}

export class TrajectoryTurn {
  turn: number = UNKNOWN_TURN;
  nodes: TrajectoryNode[] = [];

  get isUnknown(): boolean {
    return this.turn === UNKNOWN_TURN;
  }

  get toolCalls(): number {
    let n: number = 0;
    for (const node of this.nodes) {
      if (node.kind === TrajectoryNodeKind.TOOL) {
        n++;
      }
    }
    return n;
  }

  /** 按 seq 序首尾 time 差；节点不足 / 跨度非正返回 null。 */
  get durationMillis(): number | null {
    if (this.nodes.length < 2) {
      return null;
    }
    const d: number = this.nodes[this.nodes.length - 1].time - this.nodes[0].time;
    return d > 0 ? d : null;
  }
}

/** 内核过程细节不进时间轴（companion Trajectory.kt:172-185 刻意丢弃）。 */
function trajectoryKindOf(type: string): TrajectoryNodeKind | null {
  if (type === 'user/message') {
    return TrajectoryNodeKind.USER;
  }
  if (type === 'assistant/message') {
    return TrajectoryNodeKind.ASSISTANT;
  }
  if (type === 'tool/call') {
    return TrajectoryNodeKind.TOOL;
  }
  if (type === 'deliverables/presented') {
    return TrajectoryNodeKind.DELIVERABLE;
  }
  if (type === 'turn/end') {
    return TrajectoryNodeKind.TURN_END;
  }
  if (type === 'tool/result' || type === 'step/start' || type === 'step/end'
    || type === 'turn/start' || type.startsWith('session-log-')
    || type.startsWith('agent/inbox/')) {
    return null;
  }
  return TrajectoryNodeKind.OTHER;
}

function toolLabelOf(type: string, data: JsonMap | null): string {
  if (type !== 'tool/call' || data === null) {
    return '';
  }
  return JsonAccess.strOr(data, 'name', '');
}

/**
 * 把归一化后的原始事件（[{type,seq,time,data}]）按 data.turn 分组成轮次时间轴。
 * 组内按 seq 升序（不按数组顺序、不按 time）；未知轮次垫底。
 */
export function trajectoryOf(events: Object[]): TrajectoryTurn[] {
  const grouped: Map<number, TrajectoryNode[]> = new Map<number, TrajectoryNode[]>();
  for (const item of events) {
    const e: JsonMap | null = JsonAccess.asMap(item);
    if (e === null) {
      continue;
    }
    const type: string = JsonAccess.strOr(e, 'type', '');
    const kind: TrajectoryNodeKind | null = trajectoryKindOf(type);
    if (kind === null) {
      continue;
    }
    const data: JsonMap | null = JsonAccess.obj(e, 'data');
    const turnRaw: number | null = data === null ? null : JsonAccess.num(data, 'turn');
    const turn: number = turnRaw === null ? UNKNOWN_TURN : turnRaw;
    const seq: number = JsonAccess.numOr(e, 'seq', 0);
    const time: number = JsonAccess.numOr(e, 'time', 0);
    let nodes: TrajectoryNode[] | undefined = grouped.get(turn);
    if (nodes === undefined) {
      nodes = [];
      grouped.set(turn, nodes);
    }
    const node: TrajectoryNode = new TrajectoryNode();
    node.seq = seq;
    node.time = time;
    node.kind = kind;
    node.label = toolLabelOf(type, data);
    node.raw = data;
    node.type = type;
    nodes.push(node);
  }
  const turns: number[] = [];
  grouped.forEach((nodes: TrajectoryNode[], turn: number): void => {
    turns.push(turn);
  });
  turns.sort((a: number, b: number): number => {
    const aUnknown: boolean = a === UNKNOWN_TURN;
    const bUnknown: boolean = b === UNKNOWN_TURN;
    if (aUnknown !== bUnknown) {
      return aUnknown ? 1 : -1;
    }
    return a - b;
  });
  const out: TrajectoryTurn[] = [];
  for (const t of turns) {
    const nodes: TrajectoryNode[] = grouped.get(t) as TrajectoryNode[];
    nodes.sort((x: TrajectoryNode, y: TrajectoryNode): number => x.seq - y.seq);
    const turn: TrajectoryTurn = new TrajectoryTurn();
    turn.turn = t;
    turn.nodes = nodes;
    out.push(turn);
  }
  return out;
}

// ---------- 服务端投影：projections.values ----------

function valuesOf(projections: JsonMap | null): JsonMap | null {
  if (projections === null) {
    return null;
  }
  return JsonAccess.obj(projections, 'values');
}

function objectArray(raw: Object | null | undefined): JsonMap[] {
  if (raw === null || raw === undefined || !Array.isArray(raw)) {
    return [];
  }
  const out: JsonMap[] = [];
  const arr: Object[] = raw as Object[];
  for (const item of arr) {
    const m: JsonMap | null = JsonAccess.asMap(item);
    if (m !== null) {
      out.push(m);
    }
  }
  return out;
}

function stringList(raw: Object | null | undefined): string[] {
  if (raw === null || raw === undefined || !Array.isArray(raw)) {
    return [];
  }
  const out: string[] = [];
  const arr: Object[] = raw as Object[];
  for (const s of arr) {
    if (typeof s === 'string') {
      out.push(s as string);
    }
  }
  return out;
}

export class TodoItem {
  content: string = '';
  status: string = '';

  get isCompleted(): boolean {
    return this.status === 'completed';
  }

  get isInProgress(): boolean {
    return this.status === 'in_progress';
  }
}

/**
 * 只认 {content:String, status:String}；content 空白或 status 缺失丢弃。
 * 桥 fixture 的 {id,text,status} 变体同样会被丢弃（与 companion 一致）。
 */
export function todoItems(projections: JsonMap | null): TodoItem[] {
  const out: TodoItem[] = [];
  const raw: Object | null = valuesOf(projections) === null
    ? null
    : JsonAccess.raw(valuesOf(projections) as JsonMap, 'todos');
  for (const item of objectArray(raw)) {
    const content: string | null = JsonAccess.str(item, 'content');
    const status: string | null = JsonAccess.str(item, 'status');
    if (content !== null && content.trim().length > 0 && status !== null) {
      const t: TodoItem = new TodoItem();
      t.content = content;
      t.status = status;
      out.push(t);
    }
  }
  return out;
}

export class TeamMemberRow {
  id: string = '';
  name: string = '';
  role: string = '';
  phase: string = '';
  error: string = '';

  get isLead(): boolean {
    return this.role === 'lead';
  }
}

export class TeamTaskRow {
  id: string = '';
  subject: string = '';
  description: string = '';
  status: string = '';
  blockedBy: string[] = [];
  writeScopes: string[] = [];
  ownerName: string = '';
  ready: boolean = true;
}

export class SubagentRow {
  id: string = '';
  mode: string = '';
  label: string = '';
  createdAt: number | null = null;
}

export class AgentTeamProjection {
  members: TeamMemberRow[] = [];
  tasks: TeamTaskRow[] = [];
  subagents: SubagentRow[] = [];
  failure: string | null = null;

  get hasTeam(): boolean {
    return this.members.length > 0;
  }

  get completedTasks(): number {
    let n: number = 0;
    for (const t of this.tasks) {
      if (t.status === 'completed') {
        n++;
      }
    }
    return n;
  }
}

/**
 * 读 projections.values.{agentTeam,subagentCatalog}。空壳（三块都空且无
 * failure）返回 null，UI 据此显示空态；缺投影同样返回 null，但不代表功能不存在。
 */
export function agentTeamProjectionOf(projections: JsonMap | null): AgentTeamProjection | null {
  const values: JsonMap | null = valuesOf(projections);
  const team: JsonMap | null = values === null
    ? null
    : JsonAccess.obj(values, 'agentTeam');
  const failureText: string | null = team === null
    ? null
    : (() => {
      const f: string | null = JsonAccess.str(team, 'failure');
      return f !== null && f.length > 0 ? f : null;
    })();

  const members: TeamMemberRow[] = [];
  const membersRaw: Object | null = team === null
    ? null
    : JsonAccess.raw(team, 'members');
  for (const m of objectArray(membersRaw)) {
    const row: TeamMemberRow = new TeamMemberRow();
    row.id = JsonAccess.strOr(m, 'id', '');
    row.name = JsonAccess.strOr(m, 'name', row.id);
    row.role = JsonAccess.strOr(m, 'role', 'teammate');
    row.phase = JsonAccess.strOr(m, 'phase', 'active');
    row.error = JsonAccess.strOr(m, 'error', '');
    members.push(row);
  }
  const tasks: TeamTaskRow[] = [];
  const tasksRaw: Object | null = team === null ? null : JsonAccess.raw(team, 'tasks');
  for (const t of objectArray(tasksRaw)) {
    const row: TeamTaskRow = new TeamTaskRow();
    row.id = JsonAccess.strOr(t, 'id', '');
    row.subject = JsonAccess.strOr(t, 'subject', '');
    row.description = JsonAccess.strOr(t, 'description', '');
    row.status = JsonAccess.strOr(t, 'status', 'pending');
    row.blockedBy = stringList(JsonAccess.raw(t, 'blockedBy'));
    row.writeScopes = stringList(JsonAccess.raw(t, 'writeScopes'));
    row.ownerName = JsonAccess.strOr(t, 'ownerName', '');
    row.ready = JsonAccess.boolOr(t, 'ready', true);
    tasks.push(row);
  }
  const subagents: SubagentRow[] = [];
  const subsRaw: Object | null = values === null
    ? null
    : JsonAccess.raw(values, 'subagentCatalog');
  for (const s of objectArray(subsRaw)) {
    const row: SubagentRow = new SubagentRow();
    // 兼容官方 id 与老夹具 sessionId，优先 id。
    row.id = JsonAccess.strOr(s, 'id', JsonAccess.strOr(s, 'sessionId', ''));
    row.mode = JsonAccess.strOr(s, 'mode', '');
    row.label = JsonAccess.strOr(s, 'label', '');
    const created: number | null = JsonAccess.num(s, 'createdAt');
    row.createdAt = created;
    subagents.push(row);
  }
  if (members.length === 0 && tasks.length === 0 && subagents.length === 0
    && failureText === null) {
    return null;
  }
  const proj: AgentTeamProjection = new AgentTeamProjection();
  proj.members = members;
  proj.tasks = tasks;
  proj.subagents = subagents;
  proj.failure = failureText;
  return proj;
}

/** 把任意 data map 格式化成可读 JSON，供轨迹 Sheet 展开「原始事件」。 */
export function prettyJson(data: JsonMap | null): string {
  if (data === null) {
    return '（这条事件没有载荷）';
  }
  try {
    return JSON.stringify(data, null, 2);
  } catch (e) {
    return String(data);
  }
}

/** 会话统计（安卓 stats_sheet.dart chatStatsOf：本地计算不产生网络请求）。 */
export function chatStatsOf(messages: ChatMessage[]): Map<string, number> {
  let users: number = 0;
  let assistants: number = 0;
  let processes: number = 0;
  let errors: number = 0;
  let tools: number = 0;
  let thinks: number = 0;
  for (const m of messages) {
    if (m.role === 'user') {
      users++;
    } else if (m.role === 'assistant') {
      assistants++;
    } else if (m.role === 'process') {
      processes++;
    } else if (m.role === 'error') {
      errors++;
    }
    tools += m.toolCalls.length;
    if (m.reasoning.length > 0) {
      thinks++;
    }
  }
  const out: Map<string, number> = new Map();
  out.set('消息总数', messages.length);
  out.set('用户消息', users);
  out.set('助手回复', assistants);
  out.set('工具过程组', processes);
  out.set('错误提示', errors);
  out.set('工具调用', tools);
  out.set('思考块', thinks);
  return out;
}
