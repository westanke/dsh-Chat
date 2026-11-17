/**
 * core/ReasoningText.ts —— 思考行文本纯函数（官方 reasoning-text.js 逐字移植）：
 * <signature> 剥离 / firstLine / 最近完成段首行 / 摘要合成 / hidden 判定。
 */

import { test } from 'node:test';
import assert from 'node:assert';

import { reasoningFirstLine, reasoningHidden, reasoningParagraphPreview,
  reasoningSummaryOf, reasoningText } from '../../entry/src/main/ets/core/ReasoningText';

// ---- reasoningText：<signature> 剥离 --------------------------------------

test('reasoningText：非 < 开头原样；非 signature 前缀原样', () => {
  assert.equal(reasoningText('普通思考\n第二行'), '普通思考\n第二行');
  assert.equal(reasoningText(''), '');
  assert.equal(reasoningText('<think>x</think>'), '<think>x</think>');
  assert.equal(reasoningText('<signatures>x'), '<signatures>x');
});

test('reasoningText：signature 未写完/未闭合 → 空串；闭合后跳过换行', () => {
  assert.equal(reasoningText('<'), '');
  assert.equal(reasoningText('<sig'), '');
  assert.equal(reasoningText('<signature>'), '');
  assert.equal(reasoningText('<signature>abc'), '');
  assert.equal(reasoningText('<signature>abc</signature'), '');
  assert.equal(reasoningText('<signature>abc</signature>正文'), '正文');
  assert.equal(reasoningText('<signature>abc</signature>\n正文'), '正文');
  assert.equal(reasoningText('<signature>abc</signature>\n\n正文'), '正文');
  // 闭合后只跳过换行序列，其余空白保留。
  assert.equal(reasoningText('<signature>abc</signature>  正文'), '  正文');
});

// ---- reasoningFirstLine：首个 \n 前截取，不 trim ---------------------------

test('reasoningFirstLine 官方口径', () => {
  assert.equal(reasoningFirstLine('abc\ndef'), 'abc');
  assert.equal(reasoningFirstLine('  abc\nx'), '  abc');
  assert.equal(reasoningFirstLine('abc'), 'abc');
  assert.equal(reasoningFirstLine('\nabc'), '');
  assert.equal(reasoningFirstLine(''), '');
});

// ---- reasoningParagraphPreview：最近完成段的首行 ---------------------------

test('reasoningParagraphPreview：空白行分段，取最后非空候选行', () => {
  assert.equal(reasoningParagraphPreview('第一段首行\n第一段次行\n\n第二段首行\n第二段次行'), '第二段首行');
  assert.equal(reasoningParagraphPreview('只有一段\n次行'), '只有一段');
  // 候选行 trim 后非空才更新：纯空白行不覆盖。
  assert.equal(reasoningParagraphPreview('abc\n   \n\nxyz\nq'), 'xyz');
  // 段落无换行（单行段）→ 无候选产生。
  assert.equal(reasoningParagraphPreview('single'), '');
  // \r\n 换行兼容。
  assert.equal(reasoningParagraphPreview('a\r\n\r\nb\nc'), 'b');
  // tab 空白行分隔。
  assert.equal(reasoningParagraphPreview('a\n\t\n\nb'), 'a');
  assert.equal(reasoningParagraphPreview(''), '');
});

// ---- reasoningSummaryOf：running 段落预览 / 收起首行 + 去 ** ----------------

test('reasoningSummaryOf：running 与收起两路 + ** 剥离', () => {
  const raw: string = '<signature>s</signature>**加粗**首行\n次行\n\n**第二段**首行\n第二段次行';
  assert.equal(reasoningSummaryOf(raw, false), '加粗首行');
  assert.equal(reasoningSummaryOf(raw, true), '第二段首行');
  // 末段还没写出首个换行（未完成段）→ 不算候选，回落上一段。
  const streaming: string = '<signature>s</signature>第一段首行\n第一段次行\n\n第二段写到一半';
  assert.equal(reasoningSummaryOf(streaming, true), '第一段首行');
  // 非 signature 文本同样适用。
  assert.equal(reasoningSummaryOf('x\ny', true), 'x');
});

// ---- reasoningHidden：剥离后为空 → 整块不渲染 ------------------------------

test('reasoningHidden：有 signature 标记且剥离后全空 → true', () => {
  assert.equal(reasoningHidden('<signature>abc</signature>'), true);
  assert.equal(reasoningHidden('<signature>abc</signature>\n\n'), true);
  assert.equal(reasoningHidden('<sig'), true);
  // 有正文 → false。
  assert.equal(reasoningHidden('<signature>abc</signature>正文'), false);
  // 前后无差异（无 signature）→ false（即使原文全空白）。
  assert.equal(reasoningHidden('   '), false);
  assert.equal(reasoningHidden('普通'), false);
});
