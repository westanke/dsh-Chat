/**
 * Gateway 业务 API —— 对照 app/lib/bridge/gateway_api.dart（355 行 extension）。
 *
 * ArkTS 无 extension：收敛为独立 class，构造吃 GatewayClient + 可选 HttpTransport。
 * 覆盖全部非 history 端点；history()/subagentHistory() 待 HistoryPage/projections
 * 移植后补（见 harmony/docs/PORT-MAP.md 阶段 1 台账）。
 *
 * REST 口径（Android 同款，桥仓服务端实测）：
 * - 配对 POST /api/v1/pairings/exchange {code, deviceName} → {token, device}
 * - 附件 GET /api/v1/attachments/{percent-enc}?sessionId={enc}（sha256:<hex> 冒号
 *   要 encode；必须带 sessionId 否则 400 BODY_INVALID）
 * - 图片交接 GET /api/v1/image-handoff?name={enc}
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { WireBuilder } from './Wire';
import { DshSession, DshWorkspace, DshDirectoryPage, SessionWaitResult } from './Models';
import { PendingQuestion, QuestionAnswerItem } from './Questions';
import { GatewayRoot, GatewayEntry, ResolvedFile } from './Files';
import { HistoryPage } from './HistoryPage';
import { AgentPreset } from './AgentPresets';
import { RequestException } from './GatewayEvents';
import { GatewayClient } from './GatewayClient';
import { HttpTransport } from './Transport';
import { GatewayRest } from './GatewayRest';

export class GatewayApi {
  private client: GatewayClient;
  private http: HttpTransport | null;

  /** REST 端点（配对/根目录/附件/图片交接/挂起表读取）；见 GatewayRest.ts。 */
  private rest: GatewayRest;

  constructor(client: GatewayClient, http: HttpTransport | null) {
    this.client = client;
    this.http = http;
    this.rest = new GatewayRest(client, http);
  }

  // ------------------------------------------------------------------
  // REST 委托（实现在 GatewayRest.ts，公开方法名与签名保持原样）
  // ------------------------------------------------------------------

  /** 子会话（团队成员）历史 —— 只读窄口 REST（openapi.yaml:992-1050）。 */
  subagentHistory(leadSessionId: string, subagentId: string,
                  maxMessages: number = 0, beforeSeq: number = 0): Promise<HistoryPage> {
    return this.rest.subagentHistory(leadSessionId, subagentId, maxMessages, beforeSeq);
  }

  /** REST 配对（POST /api/v1/pairings/exchange；鸿蒙不走 dsh-pair 子协议）。 */
  pairViaRest(code: string, deviceName: string): Promise<JsonMap> {
    return this.rest.pairViaRest(code, deviceName);
  }

  /** 建工作区（POST /api/v1/chat/workspaces；「手机会话」准备用）。 */
  createWorkspaceRest(rootId: string, path: string): Promise<string> {
    return this.rest.createWorkspaceRest(rootId, path);
  }

  /** 工作区改名（PATCH /api/v1/chat/workspaces/{id}）。 */
  renameWorkspaceRest(workspaceId: string, title: string): Promise<void> {
    return this.rest.renameWorkspaceRest(workspaceId, title);
  }

  /** 取附件字节（base64 由调用方从 data 解码）。 */
  fetchAttachment(attachmentId: string, sessionId: string): Promise<Uint8Array> {
    return this.rest.fetchAttachment(attachmentId, sessionId);
  }

  /** Agent 预设清单（GET /chat/agent-presets → items）。 */
  agentPresets(): Promise<AgentPreset[]> {
    return this.rest.agentPresets();
  }

  /**
   * 选 Agent 预设（PUT /chat/sessions/{sid}/agent-preset）。200 返新 presetId；
   * 会话非 blank → RequestException('AGENT_PRESET_LOCKED')（409 转译在 rest 层）。
   */
  selectAgentPreset(sessionId: string, presetId: string): Promise<string> {
    return this.rest.selectAgentPreset(sessionId, presetId);
  }

  /** 授权根列表（GET /api/v1/roots）。 */
  listRootsRest(): Promise<GatewayRoot[]> {
    return this.rest.listRootsRest();
  }

  /** 会话挂起提问清单（WS replay 只补本桥前台那批，continued 只能这里拉）。 */
  fetchQuestions(sessionId: string): Promise<PendingQuestion[]> {
    return this.rest.fetchQuestions(sessionId);
  }

  /** 会话挂起提问项数（会话列表「待回答」角标用）。 */
  countPendingQuestions(sessionId: string): Promise<number> {
    return this.rest.countPendingQuestions(sessionId);
  }

  /** 会话挂起审批项数（会话列表「待审批」角标用）。 */
  countPendingApprovals(sessionId: string): Promise<number> {
    return this.rest.countPendingApprovals(sessionId);
  }

  /** 根下条目（GET /api/v1/roots/{id}/entries?path=&limit=500）。 */
  listEntriesRest(rootId: string, wirePath: string): Promise<GatewayEntry[]> {
    return this.rest.listEntriesRest(rootId, wirePath);
  }

  /** 路径解析（GET /api/v1/roots/resolve?path=；404→FILE_404）。 */
  resolvePathRest(absPath: string): Promise<ResolvedFile> {
    return this.rest.resolvePathRest(absPath);
  }

  /** 全文读取（GET /api/v1/roots/{rootId}/content?path=）。 */
  readFileBytes(rootId: string, wirePath: string): Promise<string> {
    return this.rest.readFileBytes(rootId, wirePath);
  }

  /** 取图片交接产物（sessionId 必带，否则 400 BODY_INVALID）。 */
  fetchImageHandoff(name: string, sessionId: string): Promise<Uint8Array> {
    return this.rest.fetchImageHandoff(name, sessionId);
  }

  // ------------------------------------------------------------------
  // 工作区与会话
  // ------------------------------------------------------------------

  /** 全部工作区（workspaces 帧）。 */
  workspaces(): Promise<DshWorkspace[]> {
    return this.client.request('workspaces', null).then((data: JsonMap): DshWorkspace[] => {
      return DshWorkspace.listFrom(JsonAccess.arr(data, 'workspaces'));
    });
  }

  /** 全部会话（sessions 帧；bridge 已滤 origin=='subagent'）。 */
  sessions(): Promise<DshSession[]> {
    return this.client.request('sessions', null).then((data: JsonMap): DshSession[] => {
      return DshSession.listFrom(JsonAccess.arr(data, 'sessions'));
    });
  }

  /** 在指定工作区新建会话（session-create → session-created）。 */
  createSessionInWorkspace(workspaceId: string): Promise<string> {
    const b: WireBuilder = new WireBuilder();
    b.put('workspaceId', workspaceId);
    return this.client.request('session-create', b.buildMap()).then((data: JsonMap): string => {
      return JsonAccess.strOr(data, 'sessionId', '');
    });
  }

  /** 在指定根/目录新建未分组会话（不带 workspaceId；失败显式报错不回退）。 */
  createSessionAt(rootId: string, cwd: string): Promise<string> {
    const b: WireBuilder = new WireBuilder();
    b.putNonBlank('rootId', rootId);
    b.put('cwd', cwd);
    return this.client.request('session-create', b.buildMap()).then((data: JsonMap): string => {
      // 安卓口径：sessionId 缺失/空串 → BAD_REPLY（不静默吞）。
      const sid: string = JsonAccess.strOr(data, 'sessionId', '');
      if (sid === '') {
        throw new RequestException('BAD_REPLY', 'session-create 应答缺 sessionId');
      }
      return sid;
    });
  }

  /** 列目录（file-list，limit 200；cursor 翻页）。 */
  listDirectory(rootId: string, path: string, cursor: string): Promise<DshDirectoryPage> {
    const b: WireBuilder = new WireBuilder();
    b.putNonBlank('rootId', rootId);
    b.put('path', path);
    b.putNonBlank('cursor', cursor);
    b.put('limit', 200);
    return this.client.request('file-list', b.buildMap()).then((data: JsonMap): DshDirectoryPage => {
      return DshDirectoryPage.fromJson(data);
    });
  }

  /** 建目录（directory-create；服务端 409 已存在时 error 帧打回，调用方可按幂等吞掉）。 */
  createDirectory(rootId: string, path: string): Promise<void> {
    const b: WireBuilder = new WireBuilder();
    b.putNonBlank('rootId', rootId);
    b.put('path', path);
    b.put('kind', 'directory');
    return this.client.request('directory-create', b.buildMap()).then((data: JsonMap): void => {
      return;
    });
  }

  // ------------------------------------------------------------------
  // 消息与会话推进
  // ------------------------------------------------------------------

  /** 会话历史（history 帧，支持 beforeSeq 翻页）。projections 只在首屏应答带。 */
  history(sessionId: string, maxMessages: number = 0,
          beforeSeq: number = 0): Promise<HistoryPage> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.putIf(maxMessages > 0, 'maxMessages', maxMessages);
    b.putIf(beforeSeq > 0, 'beforeSeq', beforeSeq);
    return this.client.request('history', b.buildMap()).then((data: JsonMap): HistoryPage => {
      const events: Object[] = JsonAccess.arr(data, 'events');
      const projections: JsonMap | null = JsonAccess.obj(data, 'projections');
      const hasMore: boolean = JsonAccess.boolOr(data, 'hasMore', false);
      return HistoryPage.fromEvents(events, projections, hasMore);
    });
  }

  /**
   * 发送文本消息（message 帧）。content = text 部分 + 可选图片/文件部分；
   * clientTimeZone 随帧携带（Android 口径）。
   */
  sendText(sessionId: string, text: string, mode: string = 'queue',
           contentParts: JsonMap[] = []): Promise<string> {
    const parts: JsonMap[] = [];
    const textPart: JsonMap = new WireBuilder().put('type', 'text').put('text', text).buildMap();
    parts.push(textPart);
    for (let i = 0; i < contentParts.length; i++) {
      parts.push(contentParts[i]);
    }
    const b: WireBuilder = new WireBuilder();
    b.putNonBlank('sessionId', sessionId);
    b.put('mode', mode);
    b.put('content', parts);
    b.put('clientTimeZone', this.client.clientTimeZone());
    return this.client.request('message', b.buildMap()).then((data: JsonMap): string => {
      const sid: string = JsonAccess.strOr(data, 'sessionId', '');
      return sid !== '' ? sid : sessionId;
    });
  }

  /** 取消当前轮（session-cancel；session-cancelled 在回显表内可 await）。 */
  cancelTurn(sessionId: string): Promise<JsonMap> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    return this.client.request('session-cancel', b.buildMap());
  }

  /**
   * 等待会话静默（session-wait）。timeoutMs 夹取 [1, 120000]；
   * 请求超时给 wait 超时 +5s 余量；wait 非 Map → BAD_REPLY。
   */
  sessionWait(sessionId: string, timeoutMs: number, afterSeq: number,
              maxMessages: number): Promise<SessionWaitResult> {
    let ms: number = Math.floor(timeoutMs);
    if (ms < 1) {
      ms = 1;
    }
    if (ms > 120000) {
      ms = 120000;
    }
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.put('timeoutMs', ms);
    if (afterSeq > 0) {
      b.put('afterSeq', afterSeq);
    }
    if (maxMessages > 0) {
      b.put('maxMessages', maxMessages);
    }
    return this.client.requestWithTimeout('session-wait', b.buildMap(), ms + 5000)
      .then((data: JsonMap): SessionWaitResult => {
        const wait: JsonMap | null = JsonAccess.obj(data, 'wait');
        if (wait === null) {
          throw new RequestException('BAD_REPLY', 'session-wait 应答缺少 wait 字段');
        }
        return SessionWaitResult.fromJson(wait);
      });
  }

  // ------------------------------------------------------------------
  // 权限 / 模型 / 命令
  // ------------------------------------------------------------------

  /** 权限目录原始 data（收敛逻辑在 permissions 层，models 单向依赖）。 */
  permissionOptionsRaw(): Promise<JsonMap> {
    return this.client.request('permission-options', null);
  }

  /** 设置会话权限模式（permission 帧；result.kind=='error' → PERMISSION 错）。 */
  setPermission(sessionId: string, name: string): Promise<void> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.put('name', name);
    return this.client.request('permission', b.buildMap()).then((data: JsonMap): void => {
      // 安卓口径：data.result.kind=='error' 才算失败，text 默认「切换失败」。
      const result: JsonMap | null = JsonAccess.obj(data, 'result');
      const kind: string = result === null ? '' : JsonAccess.strOr(result, 'kind', '');
      if (kind === 'error') {
        throw new RequestException('PERMISSION',
          result === null ? '切换失败' : JsonAccess.strOr(result, 'text', '切换失败'));
      }
      return;
    });
  }

  /** 会话可用模型（models 帧；收敛逻辑在 models_view 层）。 */
  sessionModels(sessionId: string): Promise<JsonMap> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    return this.client.request('models', b.buildMap());
  }

  /** 会话命令列表（commands 帧）。 */
  listCommands(sessionId: string): Promise<JsonMap> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    return this.client.request('commands', b.buildMap());
  }

  /** 执行斜杠命令（command-execute；result.kind=='error' 业务失败由调用方展示）。 */
  executeCommand(sessionId: string, line: string): Promise<JsonMap> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.put('line', line);
    return this.client.request('command-execute', b.buildMap());
  }

  /** 切换模型（select-model 帧；应答经 requestId 匹配结算）。 */
  selectModel(sessionId: string, provider: string, model: string,
              reasoningEffort: string | null): Promise<JsonMap> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.put('provider', provider);
    b.put('model', model);
    b.putNonBlank('reasoningEffort', reasoningEffort === null ? '' : reasoningEffort);
    // 应答 kind='sent'（五生产者共享），data.type=='select-model' 时带 selected。
    return this.client.request('select-model', b.buildMap());
  }

  // ------------------------------------------------------------------
  // 提问 / 审批
  // ------------------------------------------------------------------

  /** 提交问题答案（question-answer；accepted==false → QUESTION_REJECTED）。 */
  answerQuestion(sessionId: string, callId: string, answers: QuestionAnswerItem[]): Promise<void> {
    const arr: JsonMap[] = [];
    for (let i = 0; i < answers.length; i++) {
      arr.push(answers[i].toMap());
    }
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.put('callId', callId);
    b.put('answers', arr);
    return this.client.request('question-answer', b.buildMap()).then((data: JsonMap): void => {
      const accepted: boolean = JsonAccess.boolOr(data, 'accepted', true);
      if (!accepted) {
        throw new RequestException('QUESTION_REJECTED',
          JsonAccess.strOr(data, 'reason', '回答未被接受'));
      }
      return;
    });
  }

  /** 取消挂起提问（question-cancel；rpcId 优先）。 */
  cancelQuestion(sessionId: string, callId: string, rpcId: string): Promise<void> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.putNonBlank('rpcId', rpcId);
    b.put('callId', callId);
    return this.client.request('question-cancel', b.buildMap()).then((data: JsonMap): void => {
      return;
    });
  }

  /** 审批决定（approval-response；accepted==false → APPROVAL_REJECTED）。 */
  decideApproval(sessionId: string, approvalId: string, allow: boolean): Promise<void> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.put('approvalId', approvalId);
    b.put('outcome', allow ? 'allowed-once' : 'rejected');
    return this.client.request('approval-response', b.buildMap()).then((data: JsonMap): void => {
      const accepted: boolean = JsonAccess.boolOr(data, 'accepted', true);
      if (!accepted) {
        throw new RequestException('APPROVAL_REJECTED',
          JsonAccess.strOr(data, 'reason', '审批请求被拒绝'));
      }
      return;
    });
  }
}
