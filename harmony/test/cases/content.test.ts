/**
 * 消息内容部件测试 —— 对应安卓 app/lib/bridge/content.dart。
 * 覆盖：ContentParts 文本拼接规则、图片引用、交接占位符正则、
 * PromptPart 扁平类编码（ArkTS 无判别联合）、斜杠命令过滤、@ 引用草稿解析。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  ContentParts,
  ContentImageRef,
  handoffImageNameOf,
  stripBridgeImageNote,
  PromptPart,
  SlashCommandList,
  parseSlashDraft,
  parseAtMentionDraft,
} from '../../entry/src/main/ets/core/Content.ts';

test('ContentParts: content 是字符串时直接作为 text', () => {
  const c = ContentParts.from('hello');
  assert.equal(c.text, 'hello');
  assert.equal(c.reasoning, '');
  assert.equal(c.images.length, 0);
});

test('ContentParts: 数组——text 用 \\n 拼接，reasoning 用 \\n\\n 拼接', () => {
  const c = ContentParts.from([
    { type: 'text', text: '第一段' },
    { type: 'text', text: '第二段' },
    { type: 'reasoning', text: '思考A' },
    { type: 'reasoning', text: '思考B' },
  ]);
  assert.equal(c.text, '第一段\n第二段');
  assert.equal(c.reasoning, '思考A\n\n思考B');
});

test('ContentParts: image 块只收引用不收字节，空 attachmentId 丢弃', () => {
  const c = ContentParts.from([
    { type: 'image', attachment: { attachmentId: 'sha256:abc' } },
    { type: 'image', attachment: {} },
    { type: 'image' },
    { type: 'text', text: '配文' },
  ]);
  assert.equal(c.images.length, 1);
  assert.equal(c.images[0].attachmentId, 'sha256:abc');
  assert.equal(c.images[0].isValid, true);
  assert.equal(c.text, '配文');
});

test('ContentParts: 空/非法 content 不抛', () => {
  const c1 = ContentParts.from(null);
  assert.equal(c1.text, '');
  const c2 = ContentParts.from({ type: 'text' } as Object);
  assert.equal(c2.text, '');
  const c3 = ContentParts.from([null, 1, 'x'] as Object[]);
  assert.equal(c3.text, '');
  assert.equal(c3.images.length, 0);
});

test('ContentImageRef: 缺 attachment 字段时 id 为空且 invalid', () => {
  const ref = ContentImageRef.fromJson({} as Object);
  assert.equal(ref.attachmentId, '');
  assert.equal(ref.isValid, false);
});

test('handoffImageNameOf: 提取 sha256 文件名，无占位符回 null', () => {
  const hex = 'a'.repeat(64);
  const text = `前面 [Image: source: /work/.dsh-images/${hex}.png] 后面`;
  assert.equal(handoffImageNameOf(text), `${hex}.png`);
  assert.equal(handoffImageNameOf('普通文本'), null);
  assert.equal(handoffImageNameOf('[Image: source: /x/notahash.png]'), null);
});

test('PromptPart: text 工厂只带 text 字段', () => {
  const p = PromptPart.text('hi');
  assert.equal(p.type, 'text');
  assert.equal(p.text, 'hi');
  // ArkTS 扁平类（无判别联合）：键省略语义挪到 toMap() 编码侧断言。
  assert.deepEqual(p.toMap(), { type: 'text', text: 'hi' });
});

test('PromptPart: image 工厂——name 为空不出键，非空才出', () => {
  const noName = PromptPart.image('image/png', 'BASE64', null);
  assert.equal(noName.type, 'image');
  assert.equal(noName.mediaType, 'image/png');
  assert.equal(noName.data, 'BASE64');
  assert.deepEqual(noName.toMap(), {
    type: 'image',
    mediaType: 'image/png',
    data: 'BASE64',
  });

  const withName = PromptPart.image('image/png', 'BASE64', 'a.png');
  assert.equal(withName.name, 'a.png');
  assert.deepEqual(withName.toMap(), {
    type: 'image',
    mediaType: 'image/png',
    data: 'BASE64',
    name: 'a.png',
  });
});

test('PromptPart: file 工厂带 receiptId', () => {
  const p = PromptPart.file('rcpt-1');
  assert.equal(p.type, 'file');
  assert.equal(p.receiptId, 'rcpt-1');
  assert.deepEqual(p.toMap(), { type: 'file', receiptId: 'rcpt-1' });
});

test('PromptPart: toJsonString / encodeArray 往返', () => {
  const parts = [PromptPart.text('你好'), PromptPart.image('image/jpeg', 'QQ==', null)];
  assert.deepEqual(JSON.parse(PromptPart.text('hi').toJsonString()), {
    type: 'text',
    text: 'hi',
  });
  assert.deepEqual(JSON.parse(PromptPart.encodeArray(parts)), [
    { type: 'text', text: '你好' },
    { type: 'image', mediaType: 'image/jpeg', data: 'QQ==' },
  ]);
});

test('SlashCommandList: 解析命令 + builtinTokens 别名表', () => {
  const list = SlashCommandList.fromJson({
    commands: [
      { name: '/goal', description: '设定目标', input: '目标内容' },
      { name: 'plan', description: '生成计划', definitionId: 'd1', builtin: true },
      { name: 'feedback', description: '反馈', builtin: true },
    ],
    builtinTokens: {
      goal: { en: 'goal', zh: '目标' },
      plan: { en: 'plan', zh: '计划' },
    },
  } as Object);
  assert.equal(list.commands.length, 3);
  assert.equal(list.commands[0].name, 'goal'); // 前导 / 已去
  assert.equal(list.commands[0].inputHint, '目标内容');
  assert.equal(list.commands[1].definitionId, 'd1');
  assert.equal(list.commands[1].builtin, true);
  assert.equal(list.commands[2].builtin, true);
});

test('SlashCommandList.matching: 空片段回全量，不截断', () => {
  const list = SlashCommandList.fromJson({
    commands: [{ name: 'goal' }, { name: 'plan' }],
    builtinTokens: { goal: { en: 'goal', zh: '目标' } },
  } as Object);
  assert.equal(list.matching('').length, 2);
  assert.equal(list.matching('  ').length, 2);
});

test('SlashCommandList.matching: 裸名前缀 / zh 别名前缀 / en 别名前缀三路命中', () => {
  const list = SlashCommandList.fromJson({
    commands: [{ name: 'goal' }, { name: 'plan' }],
    builtinTokens: {
      goal: { en: 'goal', zh: '目标' },
      plan: { en: 'plan', zh: '计划' },
    },
  } as Object);
  assert.equal(list.matching('go').length, 1);
  assert.equal(list.matching('目标').length, 1);
  assert.equal(list.matching('计').length, 1);
  assert.equal(list.matching('zzz').length, 0);
});

test('SlashCommandList: 坏形状不抛，命令清单为空', () => {
  const list = SlashCommandList.fromJson({ commands: 'x' } as Object);
  assert.equal(list.commands.length, 0);
  assert.equal(list.builtinTokens.size, 0);
  const empty = SlashCommandList.empty();
  assert.equal(empty.commands.length, 0);
});

test('parseSlashDraft: 正常命令名+参数', () => {
  const d = parseSlashDraft('/goal 做一个计划');
  assert.ok(d !== null);
  assert.equal(d.nameFragment, 'goal');
  assert.equal(d.args, '做一个计划');
});

test('parseSlashDraft: 仅 "/" 与非法片段回全量清单', () => {
  const only = parseSlashDraft('/');
  assert.ok(only !== null);
  assert.equal(only.nameFragment, '');
  assert.equal(only.args, '');
  const zh = parseSlashDraft('/中文');
  assert.ok(zh !== null);
  assert.equal(zh.nameFragment, '中文');
  assert.equal(zh.args, '');
  assert.equal(parseSlashDraft('普通文本'), null);
});

test('parseAtMentionDraft: 光标前最近 @ 片段', () => {
  const d = parseAtMentionDraft('看看 @src/a', 9);
  assert.ok(d !== null);
  assert.equal(d.query, 'src/a');
  assert.equal(d.start, 3);
  assert.equal(d.end, 9);
});

test('parseAtMentionDraft: 邮箱不触发、空白后不触发、行首触发', () => {
  assert.equal(parseAtMentionDraft('a@b.com', 6), null);
  assert.equal(parseAtMentionDraft('@foo bar', 8), null);
  const head = parseAtMentionDraft('@abc', 4);
  assert.ok(head !== null);
  assert.equal(head.query, 'abc');
  assert.equal(head.start, 0);
  assert.equal(head.end, 4);
});

test('parseAtMentionDraft: 开括号后触发，越界回 null', () => {
  const d = parseAtMentionDraft('（@abc', 5);
  assert.ok(d !== null);
  assert.equal(d.query, 'abc');
  assert.equal(d.start, 1);
  assert.equal(d.end, 5);
  assert.equal(parseAtMentionDraft('abc', 99), null);
  assert.equal(parseAtMentionDraft('abc', -1), null);
});

test('stripBridgeImageNote: 剥掉 bridge 注入的图片说明与交接占位', () => {
  const hex = 'a0317e47b80546f76bb819814679e9c4247eefcba6cab5befa239d953784f36a';
  const raw = '这张图里主要是什么？一句话回答\n'
    + '🖼️ 图片 1「IMG_1657.png」（当前模型看不到图，已存到 .dsh-images/' + hex + '.png；'
    + '要看图，请用识图工具打开下面那行的路径）\n'
    + '[Image: source: /media/wangke/OFFICE/workspace/.dsh-mobile/.dsh-images/' + hex + '.png]';
  // 气泡只剩用户原文
  assert.equal(stripBridgeImageNote(raw), '这张图里主要是什么？一句话回答');
  // 交接文件名仍能从原文里取到（渲染缩略图用）
  assert.equal(handoffImageNameOf(raw), hex + '.png');
});

test('stripBridgeImageNote: 普通文本/纯占位/无占位都不变形', () => {
  assert.equal(stripBridgeImageNote('你好'), '你好');
  const hex = 'b'.repeat(64) + '.jpg';
  const only = '[Image: source: /a/b/' + hex + ']';
  assert.equal(stripBridgeImageNote(only), '');
  assert.equal(handoffImageNameOf(only), hex);
});
