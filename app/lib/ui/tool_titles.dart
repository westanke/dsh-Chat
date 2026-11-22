/// 官方工具行标题三段分派（task-5 对齐 dsh-client-ui-tool 0.2.2-rc.1）。
///
/// 官方 `toolTitleKey(toolName)`：
/// 1. TOOL_TITLE_KEYS 精确名表（含 SEARCH/WEB/LSP 组件覆盖，合并进本表）；
/// 2. 否则 `VARIANT_TITLE_KEYS[classifyTool(name)]`（bash/read/search/write/
///    edit/code 六变体；其余落 tool.title.generic）。
/// zh 词值取自官方合并词表（/tmp/official_zh.json，679 key）。
///
/// 偏差记录：官方 lsp 行标题按结果 kind 二段分派（查找定义/查找引用/…），
/// 我们在折叠行拿不到结果结构，统一用 tool.title.lsp（查询代码符号）。
library;

/// 官方 TOOL_VARIANTS（tool bundle:111）——精确名 → 变体；未命中 → others。
enum ToolVariant { bash, read, search, write, edit, code, others }

ToolVariant classifyTool(String bareName) => switch (bareName) {
  'bash' || 'pwsh' => ToolVariant.bash,
  'read' ||
  'read_image' ||
  'web_fetch' ||
  'cordis_package_inspect' ||
  'cordis_runtime_inspect' => ToolVariant.read,
  'web_search' || 'grep' || 'glob' => ToolVariant.search,
  'write' => ToolVariant.write,
  'edit' || 'apply_patch' => ToolVariant.edit,
  'run_code' => ToolVariant.code,
  _ => ToolVariant.others,
};

/// TOOL_TITLE_KEYS + SEARCH_TITLE_KEYS + WEB_TITLE_KEYS（zh 值）。
const Map<String, String> _toolTitles = {
  // 过程组里的推理段（bridge 用伪工具名 `thinking` 插入，见 history_page）。
  'thinking': '思考',
  'apply_patch': '应用补丁',
  'cordis_package_inspect': '查询 Cordis 环境',
  'cordis_runtime_inspect': '查询 Cordis 环境',
  'cordis_run': '运行 Cordis 插件',
  'cordis_stop': '停止 Cordis 插件',
  'cordis_undefine': '移除 Cordis 插件',
  'pwsh': '运行命令',
  'read_image': '读取图片',
  'todo_write': '更新任务清单',
  'ask_user_question': '提问',
  'create_goal': '创建目标',
  'get_goal': '查看目标',
  'update_goal': '更新目标',
  'schedule_create': '创建自动化任务',
  'schedule_list': '查看自动化任务',
  'schedule_view': '查看自动化任务详情',
  'schedule_edit': '编辑自动化任务',
  'schedule_delete': '删除自动化任务',
  'schedule_update': '修改自动化任务',
  'cordis_inspect_list': '检查提供方',
  'cordis_inspect_query': '查询运行时',
  'cordis_inspect_self': '检查动态插件',
  'workflow': '运行工作流',
  'ralph': '运行循环工作流',
  'session_event_read': '读取事件',
  'session_event_search': '搜索事件',
  'session_event_trace': '追踪事件',
  'session_search': '搜索会话',
  'session_trace': '追踪会话',
  'list_subagent_models': '查看可用模型',
  'subagent': '创建子智能体',
  'list_agents': '查看子智能体',
  'send_message': '发送消息',
  'interrupt_agent': '中断智能体',
  'job_list': '查看后台任务',
  'job_output': '读取任务输出',
  'job_kill': '取消后台任务',
  'terminal_open': '创建终端',
  'terminal_read': '读取终端',
  'terminal_list': '查看终端',
  'terminal_signal': '发送终端信号',
  'terminal_close': '关闭终端',
  'lsp': '查询代码符号',
  'spawn_teammate': '创建队友',
  'team_task_create': '创建团队任务',
  'team_task_get': '读取团队任务',
  'team_task_update': '更新团队任务',
  'team_task_list': '查看团队任务',
  'wait_agent': '等待子智能体',
  'grep': '搜索文件内容',
  'glob': '查找文件',
  'web_search': '网页搜索',
  'web_fetch': '网页获取',
};

/// VARIANT_TITLE_KEYS（zh 值）；others → tool.title.generic。
const Map<ToolVariant, String> _variantTitles = {
  ToolVariant.bash: '运行命令',
  ToolVariant.read: '读取',
  ToolVariant.search: '搜索',
  ToolVariant.write: '写入',
  ToolVariant.edit: '编辑',
  ToolVariant.code: '代码',
  ToolVariant.others: '工具调用',
};

/// 剥 `tools.` 前缀后的裸名。
String bareToolName(String toolName) =>
    toolName.startsWith('tools.') ? toolName.substring(6) : toolName;

/// 工具行标题（官方 toolTitleKey → zh）。
String toolTitle(String toolName) {
  final bare = bareToolName(toolName);
  return _toolTitles[bare] ?? _variantTitles[classifyTool(bare)]!;
}

/// tool.title.generic 工具：官方摘要带原工具名前缀（`工具调用 · <name>`）。
bool isGenericTool(String toolName) {
  final bare = bareToolName(toolName);
  return !_toolTitles.containsKey(bare) &&
      classifyTool(bare) == ToolVariant.others;
}
