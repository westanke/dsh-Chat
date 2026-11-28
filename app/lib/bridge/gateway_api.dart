/// GatewayClient 的业务帧封装（会话/工作区/权限/模型/命令）。
/// 拆出原因：宪法 §7 单文件 ≤500 行（gateway.dart WS 连接面已超线）。
///
/// 每个方法 = 一条 WS 帧（协议事实来源 asyncapi.yaml / ws-*.ts 行号见各注释）。
/// extension 放独立文件、gateway.dart import + export，消费方无感。
library;

import 'device.dart';
import 'gateway.dart';
import 'goal.dart';
import 'models.dart';
import 'queue.dart';

/// sessions 帧参数。桥只认 `archived:true`（列出归档），**没有**
/// includeArchived；默认空帧即活动会话，老桥行为不变。
Map<String, Object?> sessionsFrame({bool archived = false}) =>
    archived ? const {'archived': true} : const {};

extension GatewayApi on GatewayClient {
  /// 授权根下的工作区清单（workspaces 帧，ws-basic.ts:73-76）。
  Future<List<DshWorkspace>> workspaces() async {
    final r = await request('workspaces', const {});
    final list = r['workspaces'] as List? ?? const [];
    return list
        .map((e) => DshWorkspace.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 会话清单（sessions 帧；bridge 已过滤 origin=='subagent'）。
  ///
  /// [archived] = true 时按桥的 `sessions{archived:true}` 语义**只列已归档**
  /// （ws-basic.ts:79-84；协议没有 includeArchived 字段）。默认仍发空帧，
  /// 老桥/默认视图行为不变。
  Future<List<DshSession>> sessions({bool archived = false}) async {
    final r = await request('sessions', sessionsFrame(archived: archived));
    final list = r['sessions'] as List? ?? const [];
    return list
        .map((e) => DshSession.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 会话改名（`session-rename` 帧，ws-sessions.ts handleSessionRename）：
  /// 应答 kind=session-renamed{sessionId,title}。标题由调用方修剪/限长。
  Future<void> renameSession(String sessionId, String title) async {
    final r = await request('session-rename', {
      'sessionId': sessionId,
      'title': title,
    });
    if (r['title'] != title) {
      throw RequestException('BAD_REPLY', 'session-rename 应答标题不一致');
    }
  }

  /// 归档会话（`session-archive` 帧，ws-sessions.ts handleSessionArchive）：
  /// 只是从默认视图隐藏、日志保留（桌面端「删除」同口径）。应答 session-archived。
  Future<void> archiveSession(String sessionId) async {
    final r = await request('session-archive', {'sessionId': sessionId});
    if (r['sessionId'] != sessionId) {
      throw RequestException('BAD_REPLY', 'session-archive 应答缺 sessionId');
    }
  }

  /// 分叉会话（`fork` 帧，bridge ws-sessions.ts handleFork）：
  /// client `{sessionId, atSeq?}` → server `fork{sessionId}`（新会话 id）。
  /// 不带 [atSeq] 时由内核按当前末尾分叉；返回新会话 id，调用方负责重拉清单。
  Future<String> forkSession(String sessionId, {int? atSeq}) async {
    final r = await request('fork', {'sessionId': sessionId, 'atSeq': ?atSeq});
    final forked = r['sessionId'];
    if (forked is! String || forked.isEmpty) {
      throw RequestException('BAD_REPLY', 'fork 应答缺 sessionId');
    }
    return forked;
  }

  /// 会话待发送队列（`session-queues` 帧，bridge 22a5223 / IKX2AE）：
  /// 应答 data={sessionId, queue}；queue 缺失/形状不对回空表。
  Future<List<QueueEntry>> fetchQueue(String sessionId) async {
    final r = await request('session-queues', {'sessionId': sessionId});
    return QueueEntry.listFrom(r['queue']);
  }

  /// 队列写（`queue-update` 帧）：action=remove|steer|edit（edit 必须带 text）。
  /// 应答 data={sessionId, accepted, queue}；accepted=false 抛 RequestException，
  /// queue=null（写成功但重读失败）时返回 null，调用方需重发 [fetchQueue]。
  Future<List<QueueEntry>?> updateQueue(
    String sessionId,
    String inboxId,
    String action, {
    String? text,
  }) async {
    final r = await request('queue-update', {
      'sessionId': sessionId,
      'inboxId': inboxId,
      'action': action,
      'text': ?text,
    });
    if (r['accepted'] == false) {
      throw RequestException(
        'QUEUE_REJECTED',
        (r['reason'] ?? '队列操作未被接受') as String,
      );
    }
    final queue = r['queue'];
    return queue == null ? null : QueueEntry.listFrom(queue);
  }

  /// 提前建会话（真机反馈 2026-11-04 第 7 项）：带 [workspaceId] 走
  /// createSessionInWorkspace（复用空白会话，reuseBlank 默认 true），
  /// 新会话自动归入该工作区分组（抽屉组名 = workspace title）。
  /// 应答 kind=session-created{sessionId,workspaceId}。
  ///
  /// [agentPreset] 是「模式」（Agent 预设档位）。帧上可带（ws-sessions.ts
  /// handleSessionCreate 读 frame.agentPreset），建会话时就定好预设，
  /// 不用建完再切（空白会话之外的会话切预设会被桥锁 409）。
  Future<String> createSessionInWorkspace(
    String workspaceId, {
    String? agentPreset,
  }) async {
    final r = await request('session-create', {
      'workspaceId': workspaceId,
      'agentPreset': ?agentPreset,
    });
    final sid = r['sessionId'];
    if (sid is! String || sid.isEmpty) {
      throw RequestException('BAD_REPLY', 'session-create 应答缺 sessionId');
    }
    return sid;
  }

  /// 在授权根指定目录建会话（新建会话可选工作目录，2026-11-15 反馈）。
  /// session-create 带 rootId+cwd（ws-sessions.ts:48 handleSessionCreate，
  /// 语义与 REST POST /chat/sessions 的 [rootId,path] 一致）：[rootId] 空 =
  /// 首个授权根；[cwd] 是根内相对路径（WirePath），'' = 会话目录就是根。
  /// 不带 workspaceId → 会话落「未分组」（session_groups.dart 分组语义）。
  /// 应答 kind=session-created{sessionId,rootId}。
  /// 注意：失败必须显式报错，不要静默回退手机工作区——那等于「建到了
  /// 用户没选的地方」（ws-sessions.ts 防呆注释的同款精神）。
  ///
  /// [agentPreset] 同 createSessionInWorkspace：「模式」在建会话帧上可带。
  Future<String> createSessionAt({
    String? rootId,
    String cwd = '',
    String? agentPreset,
  }) async {
    final r = await request('session-create', {
      'rootId': ?rootId,
      'cwd': cwd,
      'agentPreset': ?agentPreset,
    });
    final sid = r['sessionId'];
    if (sid is! String || sid.isEmpty) {
      throw RequestException('BAD_REPLY', 'session-create 应答缺 sessionId');
    }
    return sid;
  }

  /// 目录浏览（file-list 帧，ws-files.ts:41；同 REST GET /roots/{id}/entries）。
  /// [path] 根内相对路径，'' = 列根目录；[rootId] 空 = 首个授权根。
  /// 应答 kind=file-list，data{rootId,path,entries,nextCursor?}。
  /// 需要 files.read scope。
  Future<DshDirectoryPage> listDirectory({
    String? rootId,
    String path = '',
    String? cursor,
  }) async {
    final r = await request('file-list', {
      'rootId': ?rootId,
      'path': path,
      'cursor': ?cursor,
      'limit': 200,
    });
    return DshDirectoryPage.fromJson(r);
  }

  /// 在授权根下建目录（directory-create 帧，files.write scope）。
  /// [path] 是根内相对路径；已存在回 409 PATH_ALREADY_EXISTS（幂等，调用方忽略）。
  Future<void> createDirectory({String? rootId, required String path}) async {
    await request('directory-create', {
      'rootId': ?rootId,
      'path': path,
      'kind': 'directory',
    });
  }

  /// REST POST /api/v1/chat/workspaces（登记工作区，实现拆 gateway_rest.dart）。
  /// body.path 是授权根内相对路径（WirePath）；目录必须已存在，幂等。
  Future<String> createWorkspaceRest({
    required String rootId,
    required String path,
  }) => gatewayCreateWorkspace(this, rootId: rootId, path: path);

  /// REST PATCH /api/v1/chat/workspaces/{id}（改工作区名，见 gateway_rest.dart）。
  Future<void> renameWorkspaceRest(String workspaceId, String title) =>
      gatewayRenameWorkspace(this, workspaceId, title);

  /// 取附件原始字节（REST GET /api/v1/attachments/{attachmentId}，
  /// openapi.yaml:348-366）：历史图片引用 sha256:`<hex>`，冒号须 percent-encode；
  /// 需要 files.read scope（设备默认 scope 含它）；响应是原始字节 + immutable
  /// 缓存。真机反馈 2026-11-04 第 1 项的取图通道。
  /// **必须带 `sessionId` query**：内核要先确认该会话的事件确实引用了这张图
  /// 才放行（bridge files.ts attachmentsAndImage，缺它回 400 BODY_INVALID）。
  Future<List<int>> fetchAttachment(String attachmentId, String sessionId) =>
      gatewayHttpBytes(
        this,
        '/api/v1/attachments/${Uri.encodeComponent(attachmentId)}'
        '?sessionId=${Uri.encodeComponent(sessionId)}',
      );

  /// 会话挂起提问清单：本桥前台挂起 + 内核 continued 合流，挂起的排前面。
  /// WS replay 只补本桥前台那批，内核 continued 只有这条清单能拉到 ——
  /// 打开会话时兜底拉一次，合流进 HitlState（chat_state._refreshPendingQuestions）。
  /// 需要 chat.read scope（设备默认 scope 含它）。
  ///
  /// 优先走 WS `questions` 帧（桥 2.17.x 起，ws-hitl.ts handleQuestions）：重连后
  /// 一次往返就能补齐两半，不必再依赖 3.0.0 要删的 REST。老桥没有这一帧、回
  /// `UNKNOWN_TYPE`，此时退回 REST `GET /api/v1/chat/sessions/{id}/questions`
  /// （routes/chat.ts:381-392）——两条路径共用同一适配层方法，items 同形。
  Future<List<PendingQuestion>> fetchQuestions(String sessionId) async {
    try {
      final r = await request('questions', {'sessionId': sessionId});
      return _pendingQuestionsFrom(sessionId, r['items']);
    } on RequestException catch (e) {
      if (e.code != 'UNKNOWN_TYPE' && e.code != 'NOT_IMPLEMENTED') rethrow;
    }
    final r = await gatewayHttpJson(
      this,
      '/api/v1/chat/sessions/${Uri.encodeComponent(sessionId)}/questions',
    );
    return _pendingQuestionsFrom(sessionId, r['items']);
  }

  /// 归一化 `questions` 应答 / REST items：两条通道同形，但都要防非 Map 元素。
  List<PendingQuestion> _pendingQuestionsFrom(String sessionId, Object? raw) => [
    for (final e in raw is List ? raw : const [])
      if (e is Map)
        PendingQuestion.from(sessionId, Map<String, dynamic>.from(e)),
  ];

  /// 取图片交接产物（REST GET /api/v1/image-handoff，openapi.yaml:314-344）：
  /// 纯文本模型发图时 bridge 把图交接成工作区 `.dsh-images/<sha256>.<ext>`，
  /// 消息文本留 [Image: source: ...] 占位。name 是裸文件名（64 位 hex + 扩展名）。
  ///
  /// **`sessionId` 必填**：bridge `attachmentsAndImage()` 强制 `name`+`sessionId`
  /// 两个 query，缺一即 400 BODY_INVALID（内核要先确认该会话授权与引用）。
  /// 姊妹仓踩过同一个坑（companion PITFALLS「image-handoff 缺 sessionId」），
  /// 本仓鸿蒙侧已带、安卓侧此前漏传——两个渠道都必须带。
  Future<List<int>> fetchImageHandoff(String name, String sessionId) =>
      gatewayHttpBytes(this, imageHandoffPath(name, sessionId));

  /// 会话统计投影（WS `session-stats` 帧，bridge ws-goals.ts:84-110）。
  /// 读内核 `session/projections` 的 `sessionStats`/`tokenUsage`/`contextPressure`，
  /// **键缺失时服务端回 null**（不是缺字段），所以三样都按可空处理。
  /// 老的 `< 2.12` 桥没有这一帧，回 `UNKNOWN_TYPE` —— 调用方捕获后回落本地估算。
  Future<Map<String, dynamic>> sessionStats(String sessionId) =>
      request('session-stats', {'sessionId': sessionId});

  /// 上下文占用投影（WS `context-usage` 帧）：同上，少一个 `sessionStats`。
  Future<Map<String, dynamic>> contextUsage(String sessionId) =>
      request('context-usage', {'sessionId': sessionId});

  /// 会话目标投影（WS `goal` 帧，bridge ws-goals.ts:44-76）：读内核
  /// `session/projections` 的 `goal`，键缺失回 null（不是缺字段）。
  /// 老桥（< 2.12）没有这一帧会回 UNKNOWN_TYPE，调用方按「无目标」处理。
  Future<GoalProjection?> fetchGoal(String sessionId) async {
    final r = await request('goal', {'sessionId': sessionId});
    return GoalProjection.fromJson(r['goal']);
  }

  /// 目标的 activation（`goals-get` 帧，bridge 22a5223 / IKX2AE）：
  /// 投影里的 goal 故意不含它（宿主进程内状态），只有这一帧拿得到。
  /// 返回 'armed' / 'disarmed'；老桥/无目标回 null（面板不显示该行）。
  Future<String?> fetchGoalActivation(String sessionId) async {
    final r = await request('goals-get', {'sessionId': sessionId});
    final activation = r['activation'];
    return activation is String && activation.isNotEmpty ? activation : null;
  }

  /// 改目标文字 / 轮次上限（`goal-edit` 帧）：compare-and-set 必须带
  /// 刚读到的 [ref]，过期会回 GOAL_STALE_REVISION。应答只回新 ref，
  /// 目标正文要重新读投影。
  Future<GoalRef?> editGoal(
    String sessionId,
    GoalRef ref, {
    String? objective,
    int? maxGoalRounds,
  }) async {
    final r = await request('goal-edit', {
      'sessionId': sessionId,
      'ref': ref.toJson(),
      'objective': ?objective,
      'maxGoalRounds': ?maxGoalRounds,
    });
    return GoalRef.fromJson(r['ref']);
  }

  /// 暂停目标（`goal-pause` 帧）：同 CAS 口径。
  Future<GoalRef?> pauseGoal(String sessionId, GoalRef ref) async {
    final r = await request('goal-pause', {
      'sessionId': sessionId,
      'ref': ref.toJson(),
    });
    return GoalRef.fromJson(r['ref']);
  }

  /// 恢复目标（`goal-resume` 帧）：同 CAS 口径。
  Future<GoalRef?> resumeGoal(String sessionId, GoalRef ref) async {
    final r = await request('goal-resume', {
      'sessionId': sessionId,
      'ref': ref.toJson(),
    });
    return GoalRef.fromJson(r['ref']);
  }

  /// 清除目标（`goal-clear` 帧）：成功后投影会给 null。
  Future<void> clearGoal(String sessionId, GoalRef ref) async {
    await request('goal-clear', {'sessionId': sessionId, 'ref': ref.toJson()});
  }

  /// 会话历史（history 帧，支持 beforeSeq 翻页——真机反馈第 5 项）。
  /// projections 只在首屏应答带（翻页不带，API.md:165,766）。
  Future<HistoryPage> history(
    String sessionId, {
    int? maxMessages,
    int? beforeSeq,
  }) async {
    // 超时按链路走：隧道放宽到 90s（首屏 600 KB 级的大帧，见 `historyTimeout` 的说明）。
    final r = await requestWithTimeout('history', {
      'sessionId': sessionId,
      'maxMessages': ?maxMessages,
      'beforeSeq': ?beforeSeq,
    }, historyTimeout);
    final events = r['events'] as List? ?? const [];
    final raw = r['projections'];
    final projections = raw is Map
        ? Map<String, dynamic>.from(raw)
        : null;
    // hasMore 从应答取真值（此前硬编码 false 导致列表到头也不提示加载更多）。
    final hasMore = r['hasMore'] == true;
    // 字节预算裁剪标记（history-byte-budget-v1）：真裁剪才带这两个字段，
    // 未裁剪时字段缺席 —— 不能把「缺席」当成「裁剪了」。
    final truncated = r['truncated'] == true;
    final bytes = r['bytes'] is int ? r['bytes'] as int : null;
    final format = r['historyFormatVersion'] is int
        ? r['historyFormatVersion'] as int
        : null;
    return HistoryPage.fromEvents(
      events,
      projections: projections,
      hasMore: hasMore,
      truncated: truncated,
      bytes: bytes,
      historyFormatVersion: format,
    );
  }

  /// 子会话（团队成员）历史 —— 只读窄口 REST
  /// GET /chat/sessions/{leadSessionId}/subagents/{subagentId}/messages
  /// （openapi.yaml:992-1050，第四轮反馈 3）。授权：Lead 可见 + 内核投影
  /// 背书成员关系；成员猜 id 不通（404）。应答形状同 history（events/hasMore）。
  Future<HistoryPage> subagentHistory(
    String leadSessionId,
    String subagentId, {
    int? maxMessages,
    int? beforeSeq,
  }) async {
    final q = <String>[
      if (maxMessages != null) 'maxMessages=$maxMessages',
      if (beforeSeq != null) 'beforeSeq=$beforeSeq',
    ];
    final path = '/api/v1/chat/sessions/$leadSessionId/subagents/'
        '$subagentId/messages${q.isEmpty ? '' : '?${q.join('&')}'}';
    final r = await gatewayHttpJson(this, path);
    final events = r['events'] as List? ?? const [];
    return HistoryPage.fromEvents(events, hasMore: r['hasMore'] == true);
  }

  /// 发消息。sessionId 省略则服务端自动建会话（响应携带新 sessionId）。
  /// contentParts 为空时发纯文本；带图时传 PromptPart.image（base64 裸串，
  /// mediaType 白名单 png/jpeg/webp/gif）。
  ///
  /// 大图不走这里：整帧超 hello.maxFrameBytes 时 chat_state.send() 改走 REST
  /// `gateway_rest.gatewaySendMessage`（12 MB body），判据 `messageFrameBytes`。
  Future<String?> sendText({
    String? sessionId,
    required String text,
    String mode = 'queue',
    List<PromptPart>? contentParts,
  }) async {
    final parts = [
      if (text.isNotEmpty) PromptPart.text(text),
      ...?contentParts,
    ];
    final r = await request(
      'message',
      messageFrameBody(
        parts: parts,
        mode: mode,
        clientTimeZone: DshDevice.ianaZone,
        sessionId: sessionId,
      ),
    );
    return r['sessionId'] as String? ?? sessionId;
  }

  /// 停止当前回合（对照 companion ChatHeader 的「停止运行」）。
  /// session-cancelled 应答不在 REQUEST_ID_ECHO_EXCLUDED_KINDS 排除表里，
  /// 会经 withRequestIdEcho 注入 data.requestId（ws-protocol.ts:611），因此
  /// 可以像其它请求一样 await（ws-sessions.ts:93-102：缺 sessionId 回
  /// MISSING_PARAMS，否则 chat.cancel 后回 {kind:'session-cancelled'}）。
  Future<void> cancelTurn(String sessionId) async {
    await request('session-cancel', {'sessionId': sessionId});
  }

  /// 长轮询会话状态（session-wait 帧；DSH 0.2.2 session/wait，桥 API.md:791
  /// 与 openapi §waitChatSession；issue #1 适配）。阻塞直到会话静止（idle）/
  /// 有待输入（input-required）/ 超时（timeout）。
  /// bridge 把 [timeoutMs] 钳 1–120000（缺省 30000）、[maxMessages] 钳 1–200；
  /// [afterSeq] 只等该事件序号之后的变化。桥侧 RPC 超时随 wait 时长放宽，
  /// 本端请求超时 = timeoutMs + 5s 余量（App 常规 30s 会先到）。
  /// 应答 session-waited 不在 REQUEST_ID_ECHO_EXCLUDED_KINDS 排除表，
  /// data={sessionId, wait:{reason,state,output}} 原样透传内核结果。
  /// 消费面说明：App 是推送型客户端（WS 订阅即实时、离线变化靠 resync 重拉），
  /// 本帧供「打开会话时对齐状态 / 无推送环境的兜底轮询」按需调用，UI 暂无
  /// 刚需页面——先落协议封装与 round-trip 测试（桥 issue 建议的优先接入项）。
  Future<SessionWaitResult> sessionWait(
    String sessionId, {
    int timeoutMs = 30000,
    int? afterSeq,
    int? maxMessages,
  }) async {
    final ms = timeoutMs.clamp(1, 120000);
    final r = await requestWithTimeout('session-wait', {
      'sessionId': sessionId,
      'timeoutMs': ms,
      'afterSeq': ?afterSeq,
      'maxMessages': ?maxMessages,
    }, Duration(milliseconds: ms + 5000));
    final wait = r['wait'];
    if (wait is! Map) {
      throw RequestException('BAD_REPLY', 'session-waited 应答缺 wait');
    }
    return SessionWaitResult.fromJson(Map<String, dynamic>.from(wait));
  }

  /// 权限档位清单（真机反馈 2026-11-04：输入条「深度思考」chip 改权限档位）。
  /// permission-options 不在排除表（ws-settings.ts:40-82），可 await；
  /// 需要 chat.read scope，缺则回 error FORBIDDEN_SCOPE。
  /// 注意：PermissionCatalog 定义在 permissions.dart（models 层单向依赖
  /// gateway 的 RequestException，gateway 不能反向 import permissions），
  /// 这里返回原始 data，由 permissions.dart 的 `parsePermissionCatalog` 收敛。
  Future<Map<String, dynamic>> permissionOptionsRaw() =>
      request('permission-options', const {});

  /// 切换会话权限档位。内部执行内核斜杠命令 `/permission name`，
  /// 不触发模型（ws-commands.ts:163-176）。result.kind == 'error' 是
  /// 业务失败（传输成功），调用方要检查并展示 result.text。
  Future<void> setPermission(String sessionId, String name) async {
    final r = await request('permission', {
      'sessionId': sessionId,
      'name': name,
    });
    final result = r['result'];
    if (result is Map && result['kind'] == 'error') {
      final text = (result['text'] ?? '切换失败') as String;
      throw RequestException('PERMISSION', text);
    }
  }

  /// 会话可用的模型清单（models 帧，sessionId 必需——ws-models.ts:51-54
  /// 缺了回 MISSING_PARAMS；应答 data 含 current/routable/groups/failures）。
  /// 应答 kind=models 在回显表内，可直接 await。原始 data 由
  /// models_view.dart 收敛成 SessionModels（models 层单向依赖）。
  Future<Map<String, dynamic>> sessionModels(String sessionId) =>
      request('models', {'sessionId': sessionId});

  /// 全局模型目录（default-model 帧，ws-settings.ts:40-58）。
  ///
  /// **不带 sessionId**：会话还没建时也能列模型（问题1：新建会话先选模型）。
  /// 应答 data 只有 {groups, failures} —— 没有 current/routable（那两个是
  /// 会话维度的）。需要 settings.read scope（在桥默认设备 scope 内）。
  /// 原始 data 由 models_view.dart 的 `ModelCatalog` 收敛。
  Future<Map<String, dynamic>> defaultModelCatalog() =>
      request('default-model', const {});

  /// 会话可用斜杠命令清单（真机反馈 2026-11-04 第 3 项）。
  /// 应答 kind=commands 在回显表内（ws-commands.ts:62-100），可直接 await；
  /// 会话激活不了时 bridge 回空清单（chat-adapter.ts:1190-1200），不报错。
  /// 原始 data 由 models.dart 的 `SlashCommandList` 收敛。
  Future<Map<String, dynamic>> listCommands(String sessionId) =>
      request('commands', {'sessionId': sessionId});

  /// 执行斜杠命令（line 直接传 "/xxx ..."，正则 `/^\/([a-z][a-z0-9_-]*)/`）。
  /// 应答 kind=command-executed 在回显表内，可 await；result.kind=='error'
  /// 是业务失败（未知命令 404 COMMAND_NOT_FOUND），调用方要展示 result.text。
  Future<Map<String, dynamic>> executeCommand({
    required String sessionId,
    required String line,
  }) => request('command-execute', {'sessionId': sessionId, 'line': line});

  /// 切换会话模型。应答 kind 是 `sent`（五个生产者共享 kind），
  /// data.type=='select-model' 才是本帧的应答（ws-models.ts:74-80）——
  /// request() 的 pending 按 requestId 关联（data 里回显），而本桥的
  /// sent 应答也带 requestId，所以可以直接 await，取 data.type 判别。
  Future<Map<String, dynamic>> selectModel({
    required String sessionId,
    required String provider,
    required String model,
    String? reasoningEffort,
  }) async {
    return request('select-model', {
      'sessionId': sessionId,
      'provider': provider,
      'model': model,
      'reasoningEffort': ?reasoningEffort,
    });
  }

  /// 回答一条提问（question-answer 帧，ws-protocol.ts:275-281）。
  /// 应答 kind=question-response data={callId, action:'answer', accepted,
  /// reason?}；accepted=false 的 reason：not-pending / reply-queued /
  /// bad-response / not-answerable（continued 态要改走 REST 答题通道）。
  /// 成功后 bridge 会推 userQuestions/answered 让卡片消失（客户端无需自删，
  /// 但 chat_state 仍会保守移除）。
  Future<void> answerQuestion({
    required String sessionId,
    required String callId,
    required List<QuestionAnswerItem> answers,
  }) async {
    final r = await request('question-answer', {
      'sessionId': sessionId,
      'callId': callId,
      'answers': [for (final a in answers) a.toJson()],
    });
    if (r['accepted'] == false) {
      throw RequestException(
        'QUESTION_REJECTED',
        (r['reason'] ?? '回答未被接受') as String,
      );
    }
  }

  /// 取消一条本桥接管的提问（question-cancel，rpcId 优先）。
  /// 应答 kind=question-response action='cancel'；continued 态取消不了。
  Future<void> cancelQuestion({
    required String sessionId,
    required String callId,
    String? rpcId,
  }) => request('question-cancel', {
    'sessionId': sessionId,
    'rpcId': ?rpcId,
    'callId': callId,
  });

  /// 工具审批决定（approval-response 帧，ws-protocol.ts:267-272）。
  /// outcome 只有 allowed-once / rejected（无「始终允许」）。
  /// 应答 kind=approval-response data.accepted=true 后 bridge 再补推
  /// approval-resolved 让卡片消失。
  Future<void> decideApproval({
    required String sessionId,
    required String approvalId,
    required bool allow,
  }) async {
    final r = await request('approval-response', {
      'sessionId': sessionId,
      'approvalId': approvalId,
      'outcome': allow ? 'allowed-once' : 'rejected',
    });
    if (r['accepted'] == false) {
      throw RequestException(
        'APPROVAL_REJECTED',
        (r['reason'] ?? '审批未被接受') as String,
      );
    }
  }

  /// Agent 预设清单（REST GET /chat/agent-presets，「代码工作视图」第三段）。
  Future<List<GatewayAgentPreset>> agentPresets() =>
      gatewayAgentPresets(this);

  /// 切换空白会话的 Agent 预设（REST PUT，409=预设已锁，由调用方处理）。
  Future<String?> selectAgentPreset(String sessionId, String presetId) =>
      gatewaySelectAgentPreset(this, sessionId, presetId);
}

/// 图片交接的请求路径（纯函数，便于单测把「两个 query 都在」钉死）：
/// `name` 是裸文件名（64 位 hex + 扩展名）、`sessionId` 是当前会话；
/// 两者都必填，缺一 bridge 回 400 BODY_INVALID。
String imageHandoffPath(String name, String sessionId) =>
    '/api/v1/image-handoff?name=${Uri.encodeComponent(name)}'
    '&sessionId=${Uri.encodeComponent(sessionId)}';
