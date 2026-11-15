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
import { QuestionAnswerItem } from './Questions';
import { RequestException } from './GatewayEvents';
import { GatewayClient } from './GatewayClient';
import { HttpRequest, HttpResponse, HttpTransport, HTTP_TIMEOUT_MS } from './Transport';

export class GatewayApi {
  private client: GatewayClient;
  private http: HttpTransport | null;

  constructor(client: GatewayClient, http: HttpTransport | null) {
    this.client = client;
    this.http = http;
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
              reasoningEffort: string): Promise<void> {
    const b: WireBuilder = new WireBuilder();
    b.put('sessionId', sessionId);
    b.put('provider', provider);
    b.put('model', model);
    b.putNonBlank('reasoningEffort', reasoningEffort);
    return this.client.request('select-model', b.buildMap()).then((data: JsonMap): void => {
      return;
    });
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

  // ------------------------------------------------------------------
  // REST（依赖注入的 HttpTransport；http 为 null 时显式报错）
  // ------------------------------------------------------------------

  private restHeaders(): Map<string, string> {
    const h: Map<string, string> = new Map();
    h.set('authorization', 'Bearer ' + this.client.getToken());
    h.set('content-type', 'application/json');
    return h;
  }

  private restJson(method: string, path: string, body: string | null,
                   okCodes: number[]): Promise<JsonMap> {
    if (this.http === null) {
      return Promise.reject(new RequestException('NO_TRANSPORT', 'HTTP 传输未注入'));
    }
    const url: string = this.client.getBaseUrl() + path;
    const req: HttpRequest = new HttpRequest(method, url, this.restHeaders(), body, HTTP_TIMEOUT_MS);
    return this.http.request(req).then((resp: HttpResponse): JsonMap => {
      let matchOk: boolean = false;
      for (let i = 0; i < okCodes.length; i++) {
        if (resp.status === okCodes[i]) {
          matchOk = true;
          break;
        }
      }
      if (!matchOk) {
        throw new RequestException('HTTP_' + resp.status.toString(),
          'REST ' + method + ' ' + path + ' -> ' + resp.status.toString());
      }
      const text: string = resp.body;
      if (text === '') {
        const empty: JsonMap = {};
        return empty;
      }
      const parsed: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(text));
      if (parsed === null) {
        throw new RequestException('BAD_REPLY', 'REST 应答不是 JSON 对象: ' + path);
      }
      return parsed;
    });
  }

  private static encodePath(part: string): string {
    return encodeURIComponent(part);
  }

  /** REST 配对（POST /api/v1/pairings/exchange；鸿蒙不走 dsh-pair 子协议）。 */
  pairViaRest(code: string, deviceName: string): Promise<JsonMap> {
    const b: WireBuilder = new WireBuilder();
    b.put('code', code);
    b.put('deviceName', deviceName);
    return this.restJson('POST', '/api/v1/pairings/exchange', JSON.stringify(b.buildMap()), [200, 201]);
  }

  /** 取附件字节（base64 由调用方从 data 解码；缺 sessionId 会 400 BODY_INVALID）。 */
  fetchAttachment(attachmentId: string, sessionId: string): Promise<string> {
    const path: string = '/api/v1/attachments/' + GatewayApi.encodePath(attachmentId)
      + '?sessionId=' + GatewayApi.encodePath(sessionId);
    if (this.http === null) {
      return Promise.reject(new RequestException('NO_TRANSPORT', 'HTTP 传输未注入'));
    }
    const req: HttpRequest = new HttpRequest('GET', this.client.getBaseUrl() + path,
      this.restHeaders(), null, HTTP_TIMEOUT_MS);
    return this.http.request(req).then((resp: HttpResponse): string => {
      if (resp.status !== 200) {
        throw new RequestException('HTTP_' + resp.status.toString(), '附件获取失败');
      }
      return resp.body;
    });
  }

  /** 取图片交接字节（GET /api/v1/image-handoff?name=enc）。 */
  fetchImageHandoff(name: string): Promise<string> {
    const path: string = '/api/v1/image-handoff?name=' + GatewayApi.encodePath(name);
    if (this.http === null) {
      return Promise.reject(new RequestException('NO_TRANSPORT', 'HTTP 传输未注入'));
    }
    const req: HttpRequest = new HttpRequest('GET', this.client.getBaseUrl() + path,
      this.restHeaders(), null, HTTP_TIMEOUT_MS);
    return this.http.request(req).then((resp: HttpResponse): string => {
      if (resp.status !== 200) {
        throw new RequestException('HTTP_' + resp.status.toString(), '图片交接获取失败');
      }
      return resp.body;
    });
  }
}
