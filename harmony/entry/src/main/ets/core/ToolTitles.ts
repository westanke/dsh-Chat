/**
 * 工具行标题三段分派（官方 dsh-client-ui-tool/lib/client.js tool-call-model 区
 * 逐字移植，zh 词表取桌面 runtime 同 bundle zh 表）：
 * ①组件级覆盖：SearchRow 用 tool.title.grep/glob、WebRow 用 tool.title.webSearch/
 *   webFetch（这四键不在 TOOL_TITLE_KEYS 表里，组件渲染时覆盖 variant 兜底）；
 * ②自有标题 TOOL_TITLE_KEYS（细化 variant 而不取代行变体）；
 * ③variant 兜底 VARIANT_TITLE_KEYS（未知工具 → others「工具调用」）。
 * 线上工具名可能带 tools. 前缀（bridge 口径），分派前剥掉。
 * `cordis_define` 官方故意缺席（ui-cordis 注册了 keyed toolview，表项不可达）。
 */

/** 扁平 key/value 对建 Map（ArkTS 禁动态键对象字面量）。 */
function mapOf(pairs: string[]): Map<string, string> {
  const out: Map<string, string> = new Map<string, string>();
  for (let i = 0; i + 1 < pairs.length; i += 2) {
    out.set(pairs[i], pairs[i + 1]);
  }
  return out;
}

/** 剥 tools. 前缀。 */
export function stripToolPrefix(name: string): string {
  if (name.startsWith('tools.')) {
    return name.substring('tools.'.length);
  }
  return name;
}

// ---- ① TOOL_VARIANTS（官方 tool-call-model.js 逐键） --------------------

const TOOL_VARIANTS: Map<string, string> = mapOf([
  'bash', 'bash',
  'pwsh', 'bash',
  'read', 'read',
  'read_image', 'read',
  'web_fetch', 'read',
  'web_search', 'search',
  'grep', 'search',
  'glob', 'search',
  'write', 'write',
  'edit', 'edit',
  'apply_patch', 'edit',
  'run_code', 'code',
  'cordis_package_inspect', 'read',
  'cordis_runtime_inspect', 'read',
  'cordis_run', 'others',
  'cordis_stop', 'others',
  'cordis_undefine', 'others',
]);

/** variant → zh 标题（官方 VARIANT_TITLE_KEYS 对应 zh 词）。 */
const VARIANT_TITLE_ZH: Map<string, string> = mapOf([
  'search', '搜索',
  'read', '读取',
  'bash', '运行命令',
  'write', '写入',
  'edit', '编辑',
  'code', '代码',
  'others', '工具调用',
]);

/** 官方 classifyTool：已知名 → variant，未知 → others。 */
export function classifyTool(name: string): string {
  const n: string = stripToolPrefix(name);
  const v: string | undefined = TOOL_VARIANTS.get(n);
  return v === undefined ? 'others' : v;
}

// ---- ② TOOL_TITLE_KEYS（官方逐键，zh 值取同 bundle 词表） ----------------

const TOOL_TITLE_ZH: Map<string, string> = mapOf([
  'apply_patch', '应用补丁',
  'cordis_package_inspect', '查询 Cordis 环境',
  'cordis_runtime_inspect', '查询 Cordis 环境',
  'cordis_run', '运行 Cordis 插件',
  'cordis_stop', '停止 Cordis 插件',
  'cordis_undefine', '移除 Cordis 插件',
  'pwsh', '运行命令',
  'read_image', '读取图片',
  'todo_write', '更新任务清单',
  'ask_user_question', '提问',
  'create_goal', '创建目标',
  'get_goal', '查看目标',
  'update_goal', '更新目标',
  'schedule_create', '创建自动化任务',
  'schedule_list', '查看自动化任务',
  'schedule_view', '查看自动化任务详情',
  'schedule_edit', '编辑自动化任务',
  'schedule_delete', '删除自动化任务',
  'schedule_update', '修改自动化任务',
  'cordis_inspect_list', '检查提供方',
  'cordis_inspect_query', '查询运行时',
  'cordis_inspect_self', '检查动态插件',
  'workflow', '运行工作流',
  'ralph', '运行循环工作流',
  'session_event_read', '读取事件',
  'session_event_search', '搜索事件',
  'session_event_trace', '追踪事件',
  'session_search', '搜索会话',
  'session_trace', '追踪会话',
  'list_subagent_models', '查看可用模型',
  'subagent', '创建子智能体',
  'list_agents', '查看子智能体',
  'send_message', '发送消息',
  'interrupt_agent', '中断智能体',
  'job_list', '查看后台任务',
  'job_output', '读取任务输出',
  'job_kill', '取消后台任务',
  'terminal_open', '创建终端',
  'terminal_read', '读取终端',
  'terminal_list', '查看终端',
  'terminal_signal', '发送终端信号',
  'terminal_close', '关闭终端',
  'lsp', '查询代码符号',
  'spawn_teammate', '创建队友',
  'team_task_create', '创建团队任务',
  'team_task_get', '读取团队任务',
  'team_task_update', '更新团队任务',
  'team_task_list', '查看团队任务',
  'wait_agent', '等待子智能体',
]);

// ---- ① 组件级覆盖（官方 SearchRow/WebRow 的键） ---------------------------

const COMPONENT_TITLE_ZH: Map<string, string> = mapOf([
  'grep', '搜索文件内容',
  'glob', '查找文件',
  'web_search', '网页搜索',
  'web_fetch', '网页获取',
]);

/** 工具行标题三段分派：组件覆盖 → 自有标题 → variant 兜底（others=工具调用）。 */
export function toolTitleOf(name: string): string {
  const n: string = stripToolPrefix(name);
  const comp: string | undefined = COMPONENT_TITLE_ZH.get(n);
  if (comp !== undefined) {
    return comp;
  }
  const owned: string | undefined = TOOL_TITLE_ZH.get(n);
  if (owned !== undefined) {
    return owned;
  }
  const variant: string | undefined = VARIANT_TITLE_ZH.get(classifyTool(n));
  return variant === undefined ? '工具调用' : variant;
}
