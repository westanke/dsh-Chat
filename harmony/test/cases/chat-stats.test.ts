/**
 * 会话统计服务端半边（core/ChatStats.ts）测试 —— 对齐安卓
 * app/lib/ui/stats_sheet.dart 的 serverStatGroups 口径：只拍平标量叶子，
 * 不翻译键名、不猜单位，空分组消失。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { ServerStatRow, serverStatRows } from '../../entry/src/main/ets/core/ChatStats.ts';
import { JsonMap } from '../../entry/src/main/ets/core/JsonAccess.ts';

function rowsOf(stats: JsonMap | null): Map<string, string> {
  const out: Map<string, string> = new Map();
  for (const r of serverStatRows(stats)) {
    out.set(r.group + '/' + r.label, r.value);
  }
  return out;
}

test('session-stats 拍平：三个容器按固定顺序、键名原样', () => {
  const stats: JsonMap = {
    sessionId: 's1',
    tokenUsage: { inputTokens: 1200, outputTokens: 340 },
    sessionStats: { turns: 3, steps: 8, ttftMs: 210 },
    contextPressure: { used: 0.25, limited: false },
  };
  const rows: ServerStatRow[] = serverStatRows(stats);
  assert.deepEqual(rows.map((r: ServerStatRow): string => r.group),
    ['服务端统计', '服务端统计', '服务端统计', 'Token 用量', 'Token 用量',
      '上下文占用', '上下文占用']);
  const m: Map<string, string> = rowsOf(stats);
  assert.equal(m.get('Token 用量/inputTokens'), '1200');
  assert.equal(m.get('服务端统计/turns'), '3');
  assert.equal(m.get('上下文占用/used'), '0.25');
  assert.equal(m.get('上下文占用/limited'), '否');
  // 顶层 sessionId 不属任何分组，不渲染
  assert.equal(m.get('服务端统计/sessionId'), undefined);
});

test('非标量 / null / 空分组一律跳过；null 输入回空数组', () => {
  const stats: JsonMap = {
    sessionStats: { turns: 2, nested: { a: 1 }, list: [1, 2], nothing: null },
    tokenUsage: {},
  };
  const m: Map<string, string> = rowsOf(stats);
  assert.equal(m.size, 1);
  assert.equal(m.get('服务端统计/turns'), '2');
  assert.equal(serverStatRows(null).length, 0);
});
