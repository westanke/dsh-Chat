/**
 * core/ToolTitles.ts —— 工具行标题三段分派（官方 dsh-client-ui-tool 逐字移植）：
 * ①组件级覆盖（SearchRow/WebRow 四键）②自有标题 TOOL_TITLE_KEYS ③variant 兜底。
 */

import { test } from 'node:test';
import assert from 'node:assert';

import { classifyTool, stripToolPrefix, toolTitleOf } from '../../entry/src/main/ets/core/ToolTitles';

test('stripToolPrefix：tools. 前缀剥离，其余原样', () => {
  assert.equal(stripToolPrefix('tools.read'), 'read');
  assert.equal(stripToolPrefix('tools.pwsh'), 'pwsh');
  assert.equal(stripToolPrefix('read'), 'read');
  assert.equal(stripToolPrefix('tools'), 'tools');
  assert.equal(stripToolPrefix(''), '');
});

test('classifyTool 官方 TOOL_VARIANTS 全表（17 键）+ 未知 others', () => {
  assert.equal(classifyTool('bash'), 'bash');
  assert.equal(classifyTool('pwsh'), 'bash');
  assert.equal(classifyTool('read'), 'read');
  assert.equal(classifyTool('read_image'), 'read');
  assert.equal(classifyTool('web_fetch'), 'read');
  assert.equal(classifyTool('web_search'), 'search');
  assert.equal(classifyTool('grep'), 'search');
  assert.equal(classifyTool('glob'), 'search');
  assert.equal(classifyTool('write'), 'write');
  assert.equal(classifyTool('edit'), 'edit');
  assert.equal(classifyTool('apply_patch'), 'edit');
  assert.equal(classifyTool('run_code'), 'code');
  assert.equal(classifyTool('cordis_package_inspect'), 'read');
  assert.equal(classifyTool('cordis_runtime_inspect'), 'read');
  assert.equal(classifyTool('cordis_run'), 'others');
  assert.equal(classifyTool('cordis_stop'), 'others');
  assert.equal(classifyTool('cordis_undefine'), 'others');
  // cordis_define 官方故意缺席（keyed toolview 表项不可达）→ others。
  assert.equal(classifyTool('cordis_define'), 'others');
  assert.equal(classifyTool('mcp__a__b'), 'others');
  assert.equal(classifyTool('tools.grep'), 'search');
});

test('toolTitleOf：组件级覆盖优先于自有标题与 variant', () => {
  assert.equal(toolTitleOf('grep'), '搜索文件内容');
  assert.equal(toolTitleOf('glob'), '查找文件');
  assert.equal(toolTitleOf('web_search'), '网页搜索');
  assert.equal(toolTitleOf('web_fetch'), '网页获取');
});

test('toolTitleOf：自有标题（TOOL_TITLE_KEYS 抽样 + 全表键数口径）', () => {
  assert.equal(toolTitleOf('pwsh'), '运行命令');
  assert.equal(toolTitleOf('todo_write'), '更新任务清单');
  assert.equal(toolTitleOf('ask_user_question'), '提问');
  assert.equal(toolTitleOf('create_goal'), '创建目标');
  assert.equal(toolTitleOf('update_goal'), '更新目标');
  assert.equal(toolTitleOf('get_goal'), '查看目标');
  assert.equal(toolTitleOf('schedule_create'), '创建自动化任务');
  assert.equal(toolTitleOf('subagent'), '创建子智能体');
  assert.equal(toolTitleOf('list_agents'), '查看子智能体');
  assert.equal(toolTitleOf('send_message'), '发送消息');
  assert.equal(toolTitleOf('interrupt_agent'), '中断智能体');
  assert.equal(toolTitleOf('wait_agent'), '等待子智能体');
  assert.equal(toolTitleOf('apply_patch'), '应用补丁');
  assert.equal(toolTitleOf('read_image'), '读取图片');
  assert.equal(toolTitleOf('run_code'), '代码');
  assert.equal(toolTitleOf('workflow'), '运行工作流');
  assert.equal(toolTitleOf('cordis_run'), '运行 Cordis 插件');
  assert.equal(toolTitleOf('terminal_open'), '创建终端');
  assert.equal(toolTitleOf('session_search'), '搜索会话');
  assert.equal(toolTitleOf('spawn_teammate'), '创建队友');
});

test('toolTitleOf：variant 兜底（无自有标题/未知工具）', () => {
  assert.equal(toolTitleOf('bash'), '运行命令');
  assert.equal(toolTitleOf('read'), '读取');
  assert.equal(toolTitleOf('write'), '写入');
  assert.equal(toolTitleOf('edit'), '编辑');
  assert.equal(toolTitleOf('mcp__x__y'), '工具调用');
  assert.equal(toolTitleOf(''), '工具调用');
  assert.equal(toolTitleOf('tools.unknown_thing'), '工具调用');
  // 自有标题优先于 variant：read_image 是 variant=read（读取）但自有「读取图片」。
  assert.notEqual(toolTitleOf('read_image'), '读取');
});
