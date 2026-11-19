/**
 * 流式渲染接线回归（2026-11-17 真机缺陷「流式思考不显示」）：
 *
 * 缺陷链（两段，缺一不可）：
 * 1) `ChatStore.send()` 在用户按发送那一刻就 `this.streaming = true` +
 *    `this.changed()`（core/ChatStore.ts:250-251），MessageList 的
 *    `streamingVisible()` 于是在第一个 reasoning delta 到达**之前**就把
 *    StreamingBlock 建成空实例。组件入参若是普通成员（无 @Prop），后续每个
 *    增量都灌不进已建好的实例 —— 块永久停在「正在思考…」占位行。
 * 2) 即使入参是 @Prop，内层 MdView 若只在 aboutToAppear 里 parseMarkdown 一次，
 *    正文也不会重解析（同为普通成员时更糟：连文本都到不了）。
 *
 * 82f6b66 只补了「把 StreamingBlock 挂进列表」这一层，两段数据流都没修，
 * 所以真机照旧不显示。本用例把这三处声明钉死成源码契约：谁把它们改回普通
 * 成员，npm test 立刻红。
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  drain, respond, respondHistory, makeReady, openSession1, userItem, ReadyCtx,
} from '../helpers/chat-ctx.ts';

const here: string = dirname(fileURLToPath(import.meta.url));

/** 读 harmony/entry/src/main/ets 下的源文件（路径相对该目录）。 */
function ets(rel: string): string {
  return readFileSync(join(here, '../../entry/src/main/ets', rel), 'utf8');
}

test('StreamingBlock：reasoning/text/showPreview 必须是 @Prop（空实例先建）', () => {
  const s: string = ets('components/StreamingBlock.ets');
  assert.match(s, /@Prop\s+reasoning\s*:\s*string/, 'reasoning 必须是 @Prop');
  assert.match(s, /@Prop\s+text\s*:\s*string/, 'text 必须是 @Prop');
  assert.match(s, /@Prop\s+showPreview\s*:\s*boolean/, 'showPreview 必须是 @Prop');
  // 三个入参都要真的传进内层组件，否则 @Prop 也没有数据来源。
  assert.match(s, /ThinkBlock\(\{\s*text:\s*this\.reasoning/, 'reasoning 要传给 ThinkBlock');
  assert.match(s, /MdView\(\{\s*text:\s*this\.text/, 'text 要传给 MdView');
});

test('ThinkBlock：text 必须是 @Prop（折叠摘要/展开正文都靠它）', () => {
  const s: string = ets('components/ThinkBlock.ets');
  assert.match(s, /@Prop\s+text\s*:\s*string/, 'text 必须是 @Prop');
  // 摘要与 hidden 都在 build 里现算，@Prop 一旦刷新就跟着变。
  assert.match(s, /reasoningSummaryOf\(this\.text/, 'summary 读 this.text');
  assert.match(s, /reasoningHidden\(this\.text/, 'hidden 读 this.text');
  // 展开正文要剥 <signature> 包裹再喂 MdView（对齐安卓 reasoningTextOf(widget.text)，
  // app/lib/ui/chat_message_blocks.dart:106）；传原文会把标签当 Markdown 渲染。
  assert.match(s, /MdView\(\{\s*text:\s*reasoningText\(this\.text\)/,
    '展开正文走 MdView(reasoningText(this.text))');
});

test('MdView：text 是 @Prop + @Watch，回调里重新 parseMarkdown', () => {
  const s: string = ets('components/md/MdView.ets');
  assert.match(s, /@Prop\s+@Watch\('onTextChange'\)\s+text\s*:\s*string/,
    'text 必须 @Prop + @Watch（否则 blocks 永远停在首帧）');
  assert.match(s, /onTextChange\(\)[^{]*\{[^}]*parseMarkdown\(this\.text\)/,
    'onTextChange 里必须重新 parseMarkdown(this.text)');
});

test('MessageList：把流式缓冲抄进 @State 再传给 StreamingBlock', () => {
  const s: string = ets('components/MessageList.ets');
  assert.match(s, /@State\s+streamTextView\s*:\s*string/, 'streamTextView 必须是 @State');
  assert.match(s, /@State\s+streamReasoningView\s*:\s*string/, 'streamReasoningView 必须是 @State');
  assert.match(s, /this\.streamTextView\s*=[^;]*st\.streamText/, 'syncVersion 抄 streamText');
  assert.match(s, /this\.streamReasoningView\s*=[^;]*st\.streamReasoning/, 'syncVersion 抄 streamReasoning');
  assert.match(s, /StreamingBlock\(\{[\s\S]{0,200}?reasoning:\s*this\.streamReasoningView/,
    'StreamingBlock 要拿到 streamReasoningView');
  // 流式块的可见性条件：**只看 st.streaming**（安卓 chat_message_list.dart:302 同口径）。
  // 2026-11-17 真机：原来还兜「残留增量未清」，TURN_END 丢帧后 streaming 已 false
  // 而缓冲留着旧文本，兜底把轮尾「正在思考…」永久钉在屏上 —— 缓冲清理归 core。
  assert.match(s, /private streamingVisible\(\)[\s\S]{0,400}?return st\.streaming;/,
    'streamingVisible 只返回 st.streaming');
  assert.doesNotMatch(s, /st\.streaming\s*\|\|\s*this\.streamTextView/,
    'streamingVisible 不得再用残留文本兜底（会钉死轮尾占位）');
});

test('send() 即建空实例：先 streaming=true/缓冲为空，delta 到达后才长出来', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  // 发送那一刻：streaming 立刻 true，两个缓冲还是空 —— 这正是 StreamingBlock
  // 被建成「空实例」的时刻（真机上第一屏就是「正在思考…」）。
  const pSend: Promise<void> = ctx.store.send('长思考一下');
  assert.equal(ctx.store.streaming, true);
  assert.equal(ctx.store.streamReasoning, '');
  assert.equal(ctx.store.streamText, '');
  respond(ctx.socket, { workspaces: [
    { id: 'ws-phone', title: '手机会话', rootId: 'r1' },
  ] });
  await drain();
  respond(ctx.socket, { sessionId: 'sid-9' });
  await drain();
  respond(ctx.socket, { type: 'message', sessionId: 'sid-9' });
  await pSend;
  // 同一个组件实例此后收到的 reasoning 增量必须能进 store（@Prop 才能把它刷上屏）。
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 'sid-9', turn: 1, step: 1, index: 0,
    kind: 'reasoning', text: '先想第一步' } });
  assert.equal(ctx.store.streamReasoning, '先想第一步');
  assert.equal(ctx.store.streamText, '');
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 'sid-9', turn: 1, step: 1, index: 1,
    kind: 'reasoning', text: '，再想第二步' } });
  assert.equal(ctx.store.streamReasoning, '先想第一步，再想第二步');
  assert.equal(ctx.store.streaming, true);
});

test('流式中途换会话：delta 只落当前会话，不污染别人', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', turn: 1, step: 1, index: 0,
    kind: 'reasoning', text: '当前会话的思考' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 'other', turn: 1, step: 1, index: 0,
    kind: 'reasoning', text: '别人的思考' } });
  assert.equal(ctx.store.streamReasoning, '当前会话的思考');
});

test('turn.end 清空缓冲：块该整块消失（不留空壳）', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', turn: 1, step: 1, index: 0,
    kind: 'reasoning', text: '收尾' } });
  assert.equal(ctx.store.streamReasoning, '收尾');
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.turn.end', sessionId: 's1', reason: { kind: 'completed' } } });
  await drain();
  // turn.end 会 reloadHistory（落库后的正式历史），补一帧应答收尾。
  respondHistory(ctx.socket, [userItem(1, 'q')]);
  await drain();
  assert.equal(ctx.store.streaming, false);
  assert.equal(ctx.store.streamReasoning, '');
  assert.equal(ctx.store.streamText, '');
});
