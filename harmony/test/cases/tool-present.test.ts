/**
 * core/ToolPresent.ts + core/ToolDetails.ts —— 官方 Web 会话页工具呈现口径
 * （activityKind/词表/过程组标题/工具行摘要/详情分派/询问状态机/policy）。
 */

import { test } from 'node:test';
import assert from 'node:assert';

import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage';
import { TOOL_STATUS_PREPARING } from '../../entry/src/main/ets/core/StreamTools';
import { ToolCallInfo } from '../../entry/src/main/ets/core/ToolCall';
import { QuestionAnswerItem } from '../../entry/src/main/ets/core/Questions';
import {
  AK_COMMANDS, AK_QUESTIONS, AK_READ, AK_TOOLS,
  activityKind, combineDoneWords, doneGroupTitle, doneWordOf, firstLineOf, hasRunningCall,
  kindIcon, liveDetailOf, processGroupTitle, reasoningTailOf, toolSummaryOf, toolTitle,
  truncateDetail, GroupTitleOptions,
} from '../../entry/src/main/ets/core/ToolPresent';
import {
  ASK_CLOSED, ASK_PENDING, ASK_WAITING, answerEntries, askQuestions, askSummaryOf,
  detailModeOf, ioInputOf, ioOutputOf, isAnswered, isGroupForceOpen, policyOf,
  readLinesOf, STEP_GROUPING_COLLAPSED, STEP_GROUPING_HISTORY, STEP_GROUPING_NONE,
} from '../../entry/src/main/ets/core/ToolDetails';

function call(name: string, rawArguments: string | null, resultText: string | null,
  failed: boolean = false): ToolCallInfo {
  return new ToolCallInfo('c-' + Math.random().toString(36).substring(2, 8), name, [], null,
    failed, null, resultText, rawArguments);
}

function msg(role: string, seq: number, text: string, streaming: boolean = false): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = role;
  m.seq = seq;
  m.text = text;
  m.streaming = streaming;
  return m;
}

// ---- activityKind -------------------------------------------------------

test('activityKind 官方归类全表（精确/前缀/后缀/tools. 剥离）', () => {
  assert.equal(activityKind('read'), 'read');
  assert.equal(activityKind('read_image'), 'readImage');
  assert.equal(activityKind('grep'), 'search');
  assert.equal(activityKind('glob'), 'search');
  assert.equal(activityKind('foo_inspect'), 'search');
  assert.equal(activityKind('write'), 'write');
  assert.equal(activityKind('edit'), 'edit');
  assert.equal(activityKind('apply_patch'), 'edit');
  assert.equal(activityKind('bash'), 'commands');
  assert.equal(activityKind('pwsh'), 'commands');
  assert.equal(activityKind('exec_command'), 'commands');
  assert.equal(activityKind('write_stdin'), 'commands');
  assert.equal(activityKind('terminal_focus'), 'commands');
  assert.equal(activityKind('run_code'), 'code');
  assert.equal(activityKind('web_search'), 'webSearch');
  assert.equal(activityKind('web_fetch'), 'webFetch');
  assert.equal(activityKind('subagent'), 'subagents');
  assert.equal(activityKind('subagent_spawn'), 'subagents');
  assert.equal(activityKind('ask_user_question'), 'questions');
  assert.equal(activityKind('todo_write'), 'plan');
  assert.equal(activityKind('memory'), 'tools');
  assert.equal(activityKind('mcp__a__b'), 'tools');
  assert.equal(activityKind('unknown_tool'), 'tools');
  assert.equal(activityKind(''), 'thinking');
  assert.equal(activityKind('tools.read'), 'read');
  assert.equal(activityKind('tools.pwsh'), 'commands');
  assert.equal(activityKind('tools.edit'), 'edit');
  assert.equal(activityKind('tools.write'), 'write');
  assert.equal(activityKind('tools.grep'), 'search');
  assert.equal(activityKind('tools.bash'), 'commands');
});

// ---- toolTitle / kindIcon -----------------------------------------------

test('toolTitle 精确特例优先，kind 表兜底，未知 → 工具调用', () => {
  assert.equal(toolTitle('pwsh'), 'Pwsh');
  assert.equal(toolTitle('tools.pwsh'), 'Pwsh');
  assert.equal(toolTitle('grep'), 'Grep');
  assert.equal(toolTitle('glob'), 'Glob');
  assert.equal(toolTitle('bash'), 'Bash');
  assert.equal(toolTitle('read'), '读取');
  assert.equal(toolTitle('edit'), '编辑');
  assert.equal(toolTitle('write'), '写入');
  assert.equal(toolTitle('todo_write'), '更新待办列表');
  assert.equal(toolTitle('subagent'), '创建子智能体');
  assert.equal(toolTitle('read_image'), '读取图像');
  assert.equal(toolTitle('ask_user_question'), '提问');
  assert.equal(toolTitle('web_search'), '搜索');
  assert.equal(toolTitle('web_fetch'), '获取');
  assert.equal(toolTitle('mcp__x__y'), '工具调用');
  assert.equal(toolTitle(''), '思考');
});

test('kindIcon 未知 kind 兜底 🔧', () => {
  assert.equal(kindIcon(AK_READ), '📄');
  assert.equal(kindIcon('mystery'), '🔧');
});

// ---- 文本工具 ------------------------------------------------------------

test('firstLineOf 首个非空行；reasoningTailOf 最后非空段去 **；truncateDetail 160 截断', () => {
  assert.equal(firstLineOf(' \nabc\ndef'), 'abc');
  assert.equal(firstLineOf('   '), '');
  assert.equal(reasoningTailOf('a\n**x**\n\nb **y**'), 'b y');
  assert.equal(reasoningTailOf('   '), '');
  const long: string = 'x'.repeat(170);
  const cut: string = truncateDetail(long);
  assert.equal(cut.length, 161);
  assert.equal(cut.endsWith('…'), true);
  assert.equal(truncateDetail('short'), 'short');
});

// ---- liveDetailOf -------------------------------------------------------

test('liveDetailOf 官方键序首个命中（数组取首项首行；截 160；无键空）', () => {
  const withTitle: ToolCallInfo = call('bash', '{"title":"T","command":"npm test"}', null);
  assert.equal(liveDetailOf(withTitle), 'T');
  const withCommand: ToolCallInfo = call('bash', '{"command":"npm test\\nvite"}', null);
  assert.equal(liveDetailOf(withCommand), 'npm test');
  const withQueries: ToolCallInfo = call('grep', '{"queries":["a\\nb","c"]}', null);
  assert.equal(liveDetailOf(withQueries), 'a');
  const queriesNonString: ToolCallInfo = call('grep', '{"queries":[1],"url":"http://x"}', null);
  assert.equal(liveDetailOf(queriesNonString), 'http://x');
  const long: string = 'y'.repeat(200);
  const truncated: ToolCallInfo = call('bash', '{"description":"' + long + '"}', null);
  assert.equal(liveDetailOf(truncated).length, 161);
  const noKeys: ToolCallInfo = call('bash', '{"foo":"bar"}', null);
  assert.equal(liveDetailOf(noKeys), '');
  const noArgs: ToolCallInfo = call('bash', null, null);
  assert.equal(liveDetailOf(noArgs), '');
});

// ---- 过程组标题 -----------------------------------------------------------

test('processGroupTitle 进行中：running 词表 + preparing 近似 + detail 附加', () => {
  const opts: GroupTitleOptions = new GroupTitleOptions();
  opts.liveProcessDetail = true;
  const running: ToolCallInfo[] = [call('read', '{"path":"/a"}', null)];
  assert.equal(processGroupTitle(running, true, opts), '正在读取文件 · /a');
  // preparing 现为真数据驱动（status 字段，StreamTools 建行时标记），不再用 rawArguments==null 近似。
  const preparingRow: ToolCallInfo = call('read', null, null);
  preparingRow.status = TOOL_STATUS_PREPARING;
  assert.equal(processGroupTitle([preparingRow], true, opts), '准备读取文件');
  const withDetail: ToolCallInfo[] = [call('bash', '{"command":"npm run build"}', null)];
  assert.equal(processGroupTitle(withDetail, true, opts), '正在运行命令 · npm run build');
  const noDetailOpts: GroupTitleOptions = new GroupTitleOptions();
  assert.equal(processGroupTitle(withDetail, true, noDetailOpts), '正在运行命令');
  const plainLabel: ToolCallInfo[] = [call('unknown_tool', '{"foo":"bar"}', null)];
  assert.equal(processGroupTitle(plainLabel, true, opts), '正在调用工具');
  const asking: ToolCallInfo[] = [call('ask_user_question', '{"question":"Q"}', null)];
  assert.equal(processGroupTitle(asking, true, opts), '等待你的操作 · Q');
});

test('processGroupTitle 进行中无 running → thinking + reasoning 尾段', () => {
  const opts: GroupTitleOptions = new GroupTitleOptions();
  opts.liveProcessDetail = true;
  opts.reasoning = '**分析要点**\n正在核对导出';
  const settled: ToolCallInfo[] = [call('read', '{"path":"/a"}', 'ok')];
  assert.equal(processGroupTitle(settled, true, opts), '正在分析请求 · 正在核对导出');
});

test('processGroupTitle 完成：单类/2 类并/3 类逗号/4 类等/空组', () => {
  const opts: GroupTitleOptions = new GroupTitleOptions();
  assert.equal(processGroupTitle([call('read', '{}', 'ok')], false, opts), '已读取文件');
  assert.equal(processGroupTitle(
    [call('read', '{}', 'ok'), call('write', '{}', 'ok')], false, opts), '已读取文件并写入文件');
  assert.equal(processGroupTitle(
    [call('read', '{}', 'ok'), call('edit', '{}', 'ok')], false, opts),
    '已读取文件并修改了文件');
  assert.equal(processGroupTitle(
    [call('read', '{}', 'ok'), call('write', '{}', 'ok'), call('grep', '{}', 'ok')],
    false, opts), '已读取文件，已写入文件，已搜索代码');
  assert.equal(processGroupTitle(
    [call('read', '{}', 'ok'), call('write', '{}', 'ok'), call('grep', '{}', 'ok'),
      call('bash', '{}', 'ok')], false, opts), '已读取文件，已写入文件，已搜索代码等');
  assert.equal(processGroupTitle([], false, opts), '已完成分析');
});

test('doneGroupTitle count 降序并列按首现序；doneWordOf 未知兜底', () => {
  const calls: ToolCallInfo[] = [
    call('edit', '{}', 'ok'), call('read', '{}', 'ok'), call('read', '{}', 'ok'),
    call('read', '{}', 'ok'), call('edit', '{}', 'ok'),
  ];
  assert.equal(doneGroupTitle(calls), '已读取文件并修改了文件');
  assert.equal(doneWordOf('mystery'), '已调用工具');
  assert.equal(combineDoneWords(['已读取文件', '已写入文件'], 2), '已读取文件并写入文件');
  assert.equal(combineDoneWords(['已读取文件', '修改了文件'], 2), '已读取文件并修改了文件');
  assert.equal(combineDoneWords([], 0), '已完成分析');
});

test('hasRunningCall 组级判定', () => {
  assert.equal(hasRunningCall([call('read', '{}', 'ok')]), false);
  assert.equal(hasRunningCall([call('read', '{}', 'ok'), call('bash', '{}', null)]), true);
});

// ---- toolSummaryOf ------------------------------------------------------

test('toolSummaryOf 键序首个命中（commands description 优先）', () => {
  const both: ToolCallInfo = call('bash', '{"description":"构建项目","command":"npm test"}', null);
  assert.equal(toolSummaryOf(both), '构建项目');
  const onlyCommand: ToolCallInfo = call('bash', '{"command":"npm test\\nvite"}', null);
  assert.equal(toolSummaryOf(onlyCommand), 'npm test');
});

test('toolSummaryOf read/write/code 路径与描述', () => {
  assert.equal(toolSummaryOf(call('read', '{"path":"/a/b.txt"}', null)), '/a/b.txt');
  assert.equal(toolSummaryOf(call('write', '{"file_path":"/a"}', null)), '/a');
  assert.equal(toolSummaryOf(call('run_code', '{"description":"跑测试"}', null)), '跑测试');
});

test('toolSummaryOf 兜底首个字符串值首行 → argsRaw 首行', () => {
  assert.equal(toolSummaryOf(call('memory', '{"foo":"bar"}', null)), 'bar');
  assert.equal(toolSummaryOf(call('read', '{"path":"\\n/a.txt"}', null)), '/a.txt');
  assert.equal(toolSummaryOf(call('read', '{"bad', null)), '{"bad');
  assert.equal(toolSummaryOf(call('read', null, null)), '');
});

// ---- 详情分派 ------------------------------------------------------------

test('detailModeOf 分派表', () => {
  assert.equal(detailModeOf(call('edit', '{}', null)), 'diff');
  assert.equal(detailModeOf(call('tools.write', '{}', null)), 'diff');
  assert.equal(detailModeOf(call('bash', '{}', null)), 'command');
  assert.equal(detailModeOf(call('read', '{}', null)), 'read');
  assert.equal(detailModeOf(call('ask_user_question', '{}', null)), 'ask');
  assert.equal(detailModeOf(call('grep', '{}', null)), 'io');
  assert.equal(detailModeOf(call('web_search', '{}', null)), 'io');
});

test('readLinesOf 按行切去尾空行', () => {
  assert.deepEqual(readLinesOf('a\nb\nc\n\n'), ['a', 'b', 'c']);
  assert.deepEqual(readLinesOf(null), []);
  assert.deepEqual(readLinesOf('a\n\nb'), ['a', '', 'b']);
});

test('ioInputOf run_code 显示 code 正文；其余 JSON 美化截 200', () => {
  assert.equal(ioInputOf(call('run_code', '{"code":"print(1)\\nprint(2)"}', null)),
    'print(1)\nprint(2)');
  assert.equal(ioInputOf(call('grep', '{"path":"/a"}', null)), '{\n  "path": "/a"\n}');
  const long: string = 'z'.repeat(250);
  const truncated: string = ioInputOf(call('grep', '{"path":"' + long + '"}', null));
  assert.equal(truncated.length, 201);
  assert.equal(truncated.endsWith('…'), true);
  assert.equal(ioInputOf(call('grep', '{bad', null)), '{bad');
  assert.equal(ioInputOf(call('grep', null, null)), '');
});

test('ioOutputOf 空结果分派未找到结果/无结果', () => {
  assert.equal(ioOutputOf(call('grep', '{}', 'out')), 'out');
  assert.equal(ioOutputOf(call('web_search', '{}', null)), '未找到结果');
  assert.equal(ioOutputOf(call('web_fetch', '{}', '')), '未找到结果');
  assert.equal(ioOutputOf(call('read', '{}', null)), '无结果');
});

// ---- 询问状态机 -----------------------------------------------------------

test('askSummaryOf 等待中/已继续/已关闭/已回答计数/坏 JSON 兜底', () => {
  assert.equal(askSummaryOf(call('ask_user_question', '{"question":"Q"}', null), true),
    ASK_WAITING);
  assert.equal(askSummaryOf(call('ask_user_question', '{}', '{"pending":true}'), true),
    ASK_PENDING);
  assert.equal(askSummaryOf(call('ask_user_question', '{}', '{"pending":true}'), false),
    ASK_CLOSED);
  const answered: string = '{"answers":[{"id":"a","selected":["yes"],"custom":""},' +
    '{"id":"b","selected":[],"custom":"hi"},' +
    '{"id":"c","selected":[],"custom":""}]}';
  assert.equal(askSummaryOf(call('ask_user_question', '{}', answered), false), '2/3 已回答');
  const fallback: ToolCallInfo = call('ask_user_question', '{}', '{"bad', false);
  fallback.summary = '原摘要';
  assert.equal(askSummaryOf(fallback, false), '原摘要');
  const noResult: ToolCallInfo = call('ask_user_question', '{}', null, false);
  noResult.summary = '原摘要';
  assert.equal(askSummaryOf(noResult, false), ASK_WAITING);
});

test('answerEntries 键 id/selected/custom；无 answers 数组 → null', () => {
  const entries: QuestionAnswerItem[] | null =
    answerEntries('{"answers":[{"id":"a","selected":["x","y"],"custom":"补充"}]}');
  assert.equal(entries === null, false);
  if (entries !== null) {
    assert.equal(entries.length, 1);
    assert.equal(entries[0].id, 'a');
    assert.deepEqual(entries[0].selected, ['x', 'y']);
    assert.equal(entries[0].custom, '补充');
  }
  assert.equal(answerEntries('{"pending":true}'), null);
  assert.equal(answerEntries('{"bad'), null);
  assert.equal(answerEntries(null), null);
  const skipped: QuestionAnswerItem[] | null =
    answerEntries('{"answers":[1,{"id":"a","selected":[],"custom":""}]}');
  assert.equal(skipped !== null && skipped.length === 1, true);
});

test('isAnswered selected/custom 非空即已答', () => {
  assert.equal(isAnswered(new QuestionAnswerItem('a', ['x'], '')), true);
  assert.equal(isAnswered(new QuestionAnswerItem('a', [], 'hi')), true);
  assert.equal(isAnswered(new QuestionAnswerItem('a', [], '')), false);
});

test('askQuestions 解析与守门（multi_select 兜底/重复 id/缺字段）', () => {
  const args: string = '{"questions":[{"id":"a","question":"Q1","multi_select":true},' +
    '{"id":"b","question":"Q2"}]}';
  const questions = askQuestions(args);
  assert.equal(questions === null, false);
  if (questions !== null) {
    assert.equal(questions.length, 2);
    assert.equal(questions[0].multiSelect, true);
    assert.equal(questions[1].multiSelect, false);
    assert.equal(questions[0].id, 'a');
  }
  assert.equal(askQuestions(
    '{"questions":[{"id":"a","question":"Q1"},{"id":"a","question":"Q2"}]}'), null);
  assert.equal(askQuestions('{"questions":[{"id":"a"}]}'), null);
  assert.equal(askQuestions('{"other":1}'), null);
  assert.equal(askQuestions('{"bad'), null);
  assert.equal(askQuestions(null), null);
});

// ---- 展示档位 policy -----------------------------------------------------

test('policyOf 官方四档表', () => {
  const concise = policyOf('concise');
  assert.equal(concise.foldCompletedTurns, true);
  assert.equal(concise.stepGrouping, STEP_GROUPING_COLLAPSED);
  assert.equal(concise.liveProcessDetail, false);
  assert.equal(concise.settledReasoningPreview, false);
  const standard = policyOf('standard');
  assert.equal(standard.liveProcessDetail, true);
  assert.equal(standard.stepGrouping, STEP_GROUPING_COLLAPSED);
  const detailed = policyOf('detailed');
  assert.equal(detailed.stepGrouping, STEP_GROUPING_HISTORY);
  const verbose = policyOf('verbose');
  assert.equal(verbose.foldCompletedTurns, false);
  assert.equal(verbose.stepGrouping, STEP_GROUPING_NONE);
  assert.equal(verbose.liveProcessDetail, false);
  assert.equal(verbose.settledReasoningPreview, true);
});

// ---- alwaysOpen ----------------------------------------------------------

test('isGroupForceOpen 同轮 user 恒展开/终回复与 error 关闭/尾随 isTurnRunning', () => {
  const group: ChatMessage = msg('process', 1, '');
  assert.equal(isGroupForceOpen([group, msg('user', 2, '继续')], 0, false), true);
  assert.equal(isGroupForceOpen([group, msg('assistant', 2, '最终')], 0, false), false);
  assert.equal(isGroupForceOpen([group, msg('error', 2, 'boom')], 0, true), false);
  assert.equal(isGroupForceOpen([group, msg('process', 2, '')], 0, true), true);
  assert.equal(isGroupForceOpen([group, msg('process', 2, '')], 0, false), false);
  assert.equal(isGroupForceOpen(
    [group, msg('assistant', 2, '草稿', true), msg('user', 3, '换方向')], 0, false), true);
});

// ---- 五态口径（行渲染推导的纯函数侧样本） ---------------------------------

test('工具行五态口径：running/failed/ok 判定与 AK 常量锚定', () => {
  const running: ToolCallInfo = call('bash', '{"command":"npm test"}', null);
  assert.equal(isCallRunningForTest(running), true);
  const failed: ToolCallInfo = call('bash', '{"command":"npm test"}', 'boom', true);
  assert.equal(isCallRunningForTest(failed), false);
  assert.equal(failed.resultText, 'boom');
  const ok: ToolCallInfo = call('bash', '{"command":"npm test"}', 'done');
  assert.equal(isCallRunningForTest(ok), false);
  assert.equal(AK_COMMANDS, 'commands');
  assert.equal(AK_QUESTIONS, 'questions');
  assert.equal(AK_READ, 'read');
  assert.equal(AK_TOOLS, 'tools');
});

function isCallRunningForTest(c: ToolCallInfo): boolean {
  return c.resultText === null && !c.failed;
}
