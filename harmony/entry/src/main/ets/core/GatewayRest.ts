/**
 * Gateway REST 端点 —— 从 GatewayApi.ts 拆出（宪法 §7 单文件 ≤500 行）。
 *
 * 契约与 GatewayApi 内部原实现逐字一致：HttpTransport 为 null 时一律
 * NO_TRANSPORT 显式报错；非预期状态码抛 HTTP_{status}。GatewayApi 保留同名
 * 公开方法并委托到这里，调用方（UI / ChatStore）无需改动。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { WireBuilder } from './Wire';
import { PendingQuestion } from './Questions';
import { GatewayRoot, GatewayEntry, ResolvedFile } from './Files';
import { HistoryPage } from './HistoryPage';
import { RequestException } from './GatewayEvents';
import { GatewayClient } from './GatewayClient';
import { HttpRequest, HttpResponse, HttpTransport, HTTP_TIMEOUT_MS } from './Transport';
import { AgentPreset } from './AgentPresets';

export class GatewayRest {
  private client: GatewayClient;
  private http: HttpTransport | null;

  constructor(client: GatewayClient, http: HttpTransport | null) {
    this.client = client;
    this.http = http;
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

  /** 建工作区（POST /api/v1/chat/workspaces；「手机会话」准备用）。 */
  createWorkspaceRest(rootId: string, path: string): Promise<string> {
    const b: WireBuilder = new WireBuilder();
    b.put('rootId', rootId);
    b.put('path', path);
    return this.restJson('POST', '/api/v1/chat/workspaces',
      JSON.stringify(b.buildMap()), [200, 201]).then((resp: JsonMap): string => {
      const workspace: JsonMap | null = JsonAccess.obj(resp, 'workspace');
      if (workspace !== null) {
        const id: string = JsonAccess.strOr(workspace, 'workspaceId', '');
        if (id !== '') {
          return id;
        }
      }
      const topId: string = JsonAccess.strOr(resp, 'id', '');
      if (topId !== '') {
        return topId;
      }
      throw new RequestException('BAD_REPLY', '建工作区响应缺少 id');
    });
  }

  /** 工作区改名（PATCH /api/v1/chat/workspaces/{id}；鸿蒙 http PATCH 为字符串透传）。 */
  renameWorkspaceRest(workspaceId: string, title: string): Promise<void> {
    const b: WireBuilder = new WireBuilder();
    b.put('title', title);
    const path: string = '/api/v1/chat/workspaces/' + GatewayRest.encodePath(workspaceId);
    return this.restJson('PATCH', path, JSON.stringify(b.buildMap()), [200])
      .then((): void => {
        return;
      });
  }

  /** 取附件字节（base64 由调用方从 data 解码；缺 sessionId 会 400 BODY_INVALID）。 */
  /** 子会话（团队成员）历史 —— 只读窄口 REST（openapi.yaml:992-1050）。 */
  subagentHistory(leadSessionId: string, subagentId: string,
                  maxMessages: number = 0, beforeSeq: number = 0): Promise<HistoryPage> {
    const q: string[] = [];
    if (maxMessages > 0) {
      q.push('maxMessages=' + maxMessages.toString());
    }
    if (beforeSeq > 0) {
      q.push('beforeSeq=' + beforeSeq.toString());
    }
    const path: string = '/api/v1/chat/sessions/' + leadSessionId
      + '/subagents/' + subagentId + '/messages'
      + (q.length === 0 ? '' : '?' + q.join('&'));
    return this.restJson('GET', path, null, [200]).then((data: JsonMap): HistoryPage => {
      const events: Object[] = JsonAccess.arr(data, 'events');
      const hasMore: boolean = JsonAccess.boolOr(data, 'hasMore', false);
      return HistoryPage.fromEvents(events, null, hasMore);
    });
  }

  fetchAttachment(attachmentId: string, sessionId: string): Promise<Uint8Array> {
    const path: string = '/api/v1/attachments/' + GatewayRest.encodePath(attachmentId)
      + '?sessionId=' + GatewayRest.encodePath(sessionId);
    if (this.http === null) {
      return Promise.reject(new RequestException('NO_TRANSPORT', 'HTTP 传输未注入'));
    }
    const req: HttpRequest = new HttpRequest('GET', this.client.getBaseUrl() + path,
      this.restHeaders(), null, HTTP_TIMEOUT_MS);
    return this.http.request(req).then((resp: HttpResponse): Uint8Array => {
      if (resp.status !== 200) {
        throw new RequestException('HTTP_' + resp.status.toString(), '附件获取失败');
      }
      if (resp.bodyBytes === null) {
        throw new RequestException('NO_BODY', '响应缺字节体');
      }
      return resp.bodyBytes;
    });
  }

  /** 取图片交接字节（GET /api/v1/image-handoff?name=enc）。 */
  /** 授权根列表（GET /api/v1/roots）。 */
  listRootsRest(): Promise<GatewayRoot[]> {
    return this.restJson('GET', '/api/v1/roots', null, [200]).then((data: JsonMap): GatewayRoot[] => {
      return GatewayRoot.listFrom(data, 'items');
    });
  }

  /**
   * 会话挂起提问清单（GET /chat/sessions/{sid}/questions，openapi §listUserQuestions）：
   * 本桥前台挂起 + 内核 continued 合流，挂起的排前面。WS replay 只补本桥前台
   * 那批，内核 continued 只有这里能拉到 —— 打开会话时兜底拉一次，合流进
   * HitlStore（ChatStore.openSession）。需要 chat.read scope（设备默认含）。
   */
  fetchQuestions(sessionId: string): Promise<PendingQuestion[]> {
    const path: string = '/api/v1/chat/sessions/' + GatewayRest.encodePath(sessionId) + '/questions';
    return this.restJson('GET', path, null, [200]).then((data: JsonMap): PendingQuestion[] => {
      const items: JsonMap[] = JsonAccess.objArr(data, 'items');
      const out: PendingQuestion[] = [];
      for (const item of items) {
        const q: PendingQuestion = PendingQuestion.fromJson(sessionId, item);
        if (q.callId.length > 0) {
          out.push(q);
        }
      }
      return out;
    });
  }

  /**
   * 会话挂起提问（GET /chat/sessions/{sid}/questions，openapi §listUserQuestions）。
   * 用来给会话列表打「待回答」标记：bridge 的 sessions 列表只对**挂起审批**
   * 下发 pendingInteraction:'approval'，挂起提问不发，客户端只能自己查。
   * 返回项数（>0 即有待答）。
   */
  countPendingQuestions(sessionId: string): Promise<number> {
    const path: string = '/api/v1/chat/sessions/' + GatewayRest.encodePath(sessionId) + '/questions';
    return this.restJson('GET', path, null, [200]).then((data: JsonMap): number => {
      return JsonAccess.arr(data, 'items').length;
    });
  }

  /** 会话挂起审批（GET /chat/sessions/{sid}/approvals）；返回项数。 */
  countPendingApprovals(sessionId: string): Promise<number> {
    const path: string = '/api/v1/chat/sessions/' + GatewayRest.encodePath(sessionId) + '/approvals';
    return this.restJson('GET', path, null, [200]).then((data: JsonMap): number => {
      return JsonAccess.arr(data, 'items').length;
    });
  }

  /** 根下条目（GET /api/v1/roots/{id}/entries?path=&limit=500；目录优先排序）。 */
  listEntriesRest(rootId: string, wirePath: string): Promise<GatewayEntry[]> {
    const encRoot: string = GatewayRest.encodePath(rootId);
    let path: string = '/api/v1/roots/' + encRoot + '/entries?path=' +
      GatewayRest.encodePath(wirePath) + '&limit=500';
    return this.restJson('GET', path, null, [200]).then((data: JsonMap): GatewayEntry[] => {
      const out: GatewayEntry[] = [];
      const arr: Object[] = JsonAccess.arr(data, 'entries');
      for (const raw of arr) {
        const e: GatewayEntry | null = GatewayEntry.fromJson(JsonAccess.asMap(raw));
        if (e !== null) {
          out.push(e);
        }
      }
      GatewayEntry.sortList(out);
      return out;
    });
  }

  /** 路径解析（GET /api/v1/roots/resolve?path=；404→FILE_404）。 */
  resolvePathRest(absPath: string): Promise<ResolvedFile> {
    return this.restJson('GET', '/api/v1/roots/resolve?path=' + GatewayRest.encodePath(absPath),
      null, [200]).then((data: JsonMap): ResolvedFile => {
      const kind: string = JsonAccess.strOr(data, 'kind', '');
      if (kind !== 'file') {
        throw new RequestException('NOT_FILE', '这不是一个文件');
      }
      return ResolvedFile.fromJson(data);
    });
  }

  /** 全文读取（GET /api/v1/roots/{rootId}/content?path=；.md 全屏查看用）。 */
  readFileBytes(rootId: string, wirePath: string): Promise<string> {
    const path: string = '/api/v1/roots/' + GatewayRest.encodePath(rootId) +
      '/content?path=' + GatewayRest.encodePath(wirePath);
    if (this.http === null) {
      return Promise.reject(new RequestException('NO_TRANSPORT', 'HTTP 传输未注入'));
    }
    const req: HttpRequest = new HttpRequest('GET', this.client.getBaseUrl() + path,
      this.restHeaders(), null, HTTP_TIMEOUT_MS);
    return this.http.request(req).then((resp: HttpResponse): string => {
      if (resp.status !== 200) {
        throw new RequestException('HTTP_' + resp.status.toString(), '文件读取失败');
      }
      return resp.body;
    });
  }

  /**
   * 取图片交接产物。**sessionId 必带**：bridge `attachmentsAndImage()` 对
   * `/api/v1/image-handoff` 校验 `if (!name || !sessionId) throw ApiError(400,
   * 'BODY_INVALID', 'name and sessionId query parameters are required.')`
   * —— 只传 name 会 400（真机表现：用户气泡图片位显示「图片加载失败」）。
   */
  fetchImageHandoff(name: string, sessionId: string): Promise<Uint8Array> {
    const path: string = '/api/v1/image-handoff?name=' + GatewayRest.encodePath(name)
      + '&sessionId=' + GatewayRest.encodePath(sessionId);
    if (this.http === null) {
      return Promise.reject(new RequestException('NO_TRANSPORT', 'HTTP 传输未注入'));
    }
    const req: HttpRequest = new HttpRequest('GET', this.client.getBaseUrl() + path,
      this.restHeaders(), null, HTTP_TIMEOUT_MS);
    return this.http.request(req).then((resp: HttpResponse): Uint8Array => {
      if (resp.status !== 200) {
        throw new RequestException('HTTP_' + resp.status.toString(), '图片交接获取失败');
      }
      if (resp.bodyBytes === null) {
        throw new RequestException('NO_BODY', '响应缺字节体');
      }
      return resp.bodyBytes;
    });
  }

  // ------------------------------------------------------------------
  // Agent 预设（openapi §AgentPreset / §selectSessionAgentPreset）
  // ------------------------------------------------------------------

  /** 预设清单（GET /chat/agent-presets → {items: AgentPreset[]}）。 */
  agentPresets(): Promise<AgentPreset[]> {
    if (this.http === null) {
      return Promise.reject(new RequestException('NO_TRANSPORT', 'HTTP 传输未注入'));
    }
    return this.restJson('GET', '/api/v1/chat/agent-presets', null, [200])
      .then((data: JsonMap): AgentPreset[] => AgentPreset.listFrom(JsonAccess.arr(data, 'items')));
  }

  /**
   * 选预设（PUT /chat/sessions/{sid}/agent-preset body {agentPreset}）。
   * 200 返 {agentPreset: string}（字符串不是对象）；会话非 blank 已锁定 →
   * 桥返 409（okCodes 不含，restJson 抛 HTTP_409），这里转译成
   * RequestException AGENT_PRESET_LOCKED 供 UI 行内提示。
   */
  selectAgentPreset(sessionId: string, presetId: string): Promise<string> {
    const path: string = '/api/v1/chat/sessions/' + GatewayRest.encodePath(sessionId) + '/agent-preset';
    const body: JsonMap = {};
    body['agentPreset'] = presetId;
    if (this.http === null) {
      return Promise.reject(new RequestException('NO_TRANSPORT', 'HTTP 传输未注入'));
    }
    return this.restJson('PUT', path, JSON.stringify(body), [200])
      .then((data: JsonMap): string => {
        const preset: string = JsonAccess.strOr(data, 'agentPreset', '');
        if (preset === '') {
          throw new RequestException('BAD_REPLY', 'agentPreset 响应缺字段');
        }
        return preset;
      })
      .catch((err: Object): string => {
        if (err instanceof RequestException && err.code === 'HTTP_409') {
          throw new RequestException('AGENT_PRESET_LOCKED', '会话已锁定，仅空白会话可切换');
        }
        throw err as Error;
      });
  }
}
