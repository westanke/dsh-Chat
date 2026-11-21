/**
 * 斜杠命令面板数据面测试 —— 对应安卓 app/test/slash_commands_test.dart。
 * 覆盖：宿主命令按 definitionId 中文化、隐藏 export、四条客户端功能命令、
 * 技能目录解析、三层合并顺序与去重、四档过滤排序、中文名精确解析。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { SlashCommand, SlashCommandKind } from '../../entry/src/main/ets/core/Content.ts';
import {
  appSlashCommands,
  paletteHostCommands,
  paletteSkillCommands,
  mergePaletteCommands,
  filterPaletteCommands,
  resolvePaletteCommand,
  localizeHostCommand,
  skillsListArgs,
  isAppCommand,
  SLASH_ORDER,
  resetSlashDismissalOn,
} from '../../entry/src/main/ets/core/SlashCommands.ts';

function host(name: string, definitionId: string | null, input?: Object | null): SlashCommand {
  const j: Record<string, Object> = { name, description: '内核英文描述' };
  if (definitionId !== null) {
    j['definitionId'] = definitionId;
  }
  if (input !== undefined && input !== null) {
    j['input'] = input;
  }
  return SlashCommand.fromJson(j as Object);
}

test('SlashCommand: 解析 input 的 {hint} 对象（桥 v2.11.0 形状）', () => {
  const c = host('goal', '@deepseek-ai/dsh-command-goal', { hint: '<目标>' });
  assert.equal(c.inputHint, '<目标>');
  assert.equal(c.takesInput(), true);
});

test('SlashCommand: input 缺省 / 字符串 / 无 hint 对象都宽容', () => {
  assert.equal(host('a', null).inputHint, null);
  assert.equal(host('b', null, '文本参数').inputHint, '文本参数');
  assert.equal(host('c', null, { attachments: true }).inputHint, null);
});

test('SlashCommand.displayLabel: 无中文名回落到裸名', () => {
  assert.equal(host('todos', null).displayLabel(), 'todos');
});

test('客户端四条功能命令：名字、中文名、来源', () => {
  const app = appSlashCommands();
  assert.deepEqual(app.map((c: SlashCommand) => c.name), ['new', 'model', 'export', 'features']);
  assert.deepEqual(app.map((c: SlashCommand) => c.displayLabel()), ['新对话', '模型', '导出日志', '全部功能']);
  assert.equal(app.every((c: SlashCommand) => c.kind === SlashCommandKind.App), true);
  assert.equal(app.every((c: SlashCommand) => isAppCommand(c)), true);
});

test('宿主命令中文化：按 definitionId 换官方中文 label/描述/参数占位', () => {
  const compact = localizeHostCommand(host('compact', '@deepseek-ai/dsh-command-compact'));
  assert.equal(compact.displayLabel(), '压缩');
  assert.equal(compact.description, '压缩以上对话内容，腾出上下文');

  // 内核声明了参数（input 是对象）才会用 face.hint —— 与 dsh-go 同口径。
  const perm = localizeHostCommand(host('permission', '@deepseek-ai/dsh-permission-presets', { hint: 'x' }));
  assert.equal(perm.displayLabel(), '权限');
  assert.equal(perm.inputHint, '<预设名>');

  const plan = localizeHostCommand(host('plan', '@deepseek-ai/dsh-plan-mode', { hint: 'x' }));
  assert.equal(plan.inputHint, '[off | 要求]');

  const goal = localizeHostCommand(host('goal', '@deepseek-ai/dsh-command-goal', { hint: 'y' }));
  assert.equal(goal.inputHint, '[目标 | clear | pause | resume]');

  const fb = localizeHostCommand(host('feedback', '@deepseek-ai/dsh-command-feedback', { hint: 'q' }));
  assert.equal(fb.displayLabel(), '反馈');
  assert.equal(fb.inputHint, '<内容>');
});

test('宿主命令中文化：内核没声明参数就不硬加 hint', () => {
  const compact = localizeHostCommand(host('compact', '@deepseek-ai/dsh-command-compact'));
  assert.equal(compact.takesInput(), false);
});

test('宿主命令中文化：隐藏 export，插件命令保留内核原文', () => {
  const list = paletteHostCommands([
    host('goal', '@deepseek-ai/dsh-command-goal'),
    host('export', '@deepseek-ai/dsh-session-log-export'),
    host('todos', 'plugin:todos'),
  ]);
  assert.deepEqual(list.map((c: SlashCommand) => c.name), ['goal', 'todos']);
  assert.equal(list[1].displayLabel(), 'todos');
});

test('宿主命令中文化：没有 definitionId 的旧桥条目按名字兜底', () => {
  const goal = localizeHostCommand(host('goal', null));
  assert.equal(goal.displayLabel(), '目标');
});

test('技能目录：解析 {skills:[…]}，缺名字的条目跳过', () => {
  const skills = paletteSkillCommands({
    skills: [
      { name: 'pdf', description: '处理 PDF', whenToUse: '读文档时', modelInvocable: true },
      { description: '没有名字' },
      { name: '', description: '空名' },
    ],
  });
  assert.equal(skills.length, 1);
  assert.equal(skills[0].name, 'pdf');
  assert.equal(skills[0].kind, SlashCommandKind.Skill);
  assert.equal(skills[0].displayLabel(), 'pdf');
  assert.equal(skills[0].whenToUse, '读文档时');
  assert.equal(skills[0].takesInput(), false);
});

test('技能目录：也接受裸数组与异常形状（失败不抛）', () => {
  assert.equal(paletteSkillCommands([{ name: 'a' }]).length, 1);
  assert.equal(paletteSkillCommands(null).length, 0);
  assert.equal(paletteSkillCommands('x').length, 0);
  assert.equal(paletteSkillCommands({ skills: 'x' }).length, 0);
});

test('三层合并：客户端 → first-party → 其余（按名字），去重以先出现者为准', () => {
  const hostCmds = paletteHostCommands([
    host('compact', '@deepseek-ai/dsh-command-compact'),
    host('goal', '@deepseek-ai/dsh-command-goal'),
    host('export', '@deepseek-ai/dsh-session-log-export'),
    host('permission', '@deepseek-ai/dsh-permission-presets'),
    host('plan', '@deepseek-ai/dsh-plan-mode'),
    host('feedback', '@deepseek-ai/dsh-command-feedback'),
    host('todos', 'plugin:todos'),
  ]);
  const skills = paletteSkillCommands([{ name: 'pdf' }, { name: 'goal' }]);
  const merged = mergePaletteCommands(hostCmds, skills);
  assert.deepEqual(merged.map((c: SlashCommand) => c.name), [
    'new', 'model', 'compact', 'permission', 'plan', 'goal', 'feedback',
    'export', 'features', 'todos', 'pdf',
  ]);
  // 同名以先出现者为准：goal 仍是宿主（有中文名），不是技能。
  const goal = merged[5];
  assert.equal(goal.kind, SlashCommandKind.Host);
  assert.equal(goal.displayLabel(), '目标');
});

test('三层合并：没有宿主命令时仍给客户端功能（离线/老桥可用）', () => {
  const merged = mergePaletteCommands([], []);
  assert.deepEqual(merged.map((c: SlashCommand) => c.name),
    ['new', 'model', 'export', 'features']);
});

test('过滤：裸名前缀 / 中文名前缀都命中，同级保序', () => {
  const palette = mergePaletteCommands(paletteHostCommands([
    host('goal', '@deepseek-ai/dsh-command-goal'),
    host('compact', '@deepseek-ai/dsh-command-compact'),
  ]), []);
  assert.deepEqual(filterPaletteCommands(palette, 'mo').map((c: SlashCommand) => c.name),
    ['model']);
  assert.deepEqual(filterPaletteCommands(palette, '目').map((c: SlashCommand) => c.name),
    ['goal']);
  assert.deepEqual(filterPaletteCommands(palette, '压').map((c: SlashCommand) => c.name),
    ['compact']);
});

test('过滤：前缀优先于包含，包含优先于子序列', () => {
  const palette = mergePaletteCommands(paletteHostCommands([
    host('plan', '@deepseek-ai/dsh-plan-mode'),
  ]), []);
  assert.deepEqual(filterPaletteCommands(palette, 'plan').map((c: SlashCommand) => c.name),
    ['plan']);
  assert.deepEqual(filterPaletteCommands(palette, 'lan').map((c: SlashCommand) => c.name),
    ['plan']);
});

test('过滤：空片段回全量，无命中回空', () => {
  const palette = mergePaletteCommands([], []);
  assert.equal(filterPaletteCommands(palette, '').length, palette.length);
  assert.equal(filterPaletteCommands(palette, 'zzzz').length, 0);
});

test('精确解析：裸名与中文名都能解析', () => {
  const palette = mergePaletteCommands(paletteHostCommands([
    host('goal', '@deepseek-ai/dsh-command-goal'),
  ]), []);
  assert.equal(resolvePaletteCommand(palette, 'goal')?.name, 'goal');
  assert.equal(resolvePaletteCommand(palette, '目标')?.name, 'goal');
  assert.equal(resolvePaletteCommand(palette, '新对话')?.name, 'new');
  assert.equal(resolvePaletteCommand(palette, 'nope'), null);
  assert.equal(resolvePaletteCommand(palette, ''), null);
});

test('skillsListArgs: 内核要求包一层 request', () => {
  assert.deepEqual(skillsListArgs('s-1'), { request: { sessionId: 's-1' } });
});

test('SLASH_ORDER: 与 dsh-go _order 一致', () => {
  assert.deepEqual(SLASH_ORDER, [
    'new', 'model', 'compact', 'permission', 'plan', 'goal', 'feedback',
    'export', 'features',
  ]);
});

test('面板关闭复位：没关过不动 / 文本不变保持', () => {
  assert.equal(resetSlashDismissalOn('', '/go'), '');
  assert.equal(resetSlashDismissalOn('/go', '/go'), '/go');
  assert.equal(resetSlashDismissalOn('/goal ', '/goal '), '/goal ');
});

test('面板关闭复位：离开斜杠输入就放开', () => {
  assert.equal(resetSlashDismissalOn('/go', 'hello'), '');
  assert.equal(resetSlashDismissalOn('/go', ''), '');
});

test('面板关闭复位：重敲裸斜杠才重开，本来就关裸斜杠不重开', () => {
  assert.equal(resetSlashDismissalOn('/goal ', '/'), '');
  assert.equal(resetSlashDismissalOn('/', '/'), '/');
});

test('面板关闭复位：关掉后继续打名字仍保持关闭，只跟文本走', () => {
  assert.equal(resetSlashDismissalOn('/go', '/goa'), '/goa');
});
