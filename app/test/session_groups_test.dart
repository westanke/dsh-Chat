/// 会话抽屉分组测试 —— 真机反馈 2026-11-16：**先按时间（今天/昨天/更早）
/// 分桶、桶内按工作区聚合，超过 2 天收进可折叠「更早」**。
/// 用例与鸿蒙 `harmony/test/cases/session-groups.test.ts` 对齐（同语义两实现）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/ui/session_groups.dart';

/// 固定基准时间（与 harmony 用例同一天），避免「今天」漂移。
final DateTime now = DateTime(2026, 11, 16, 12, 0);

/// 距 [now] [daysAgo] 天、当日 [hour] 点的毫秒时间戳。
int ms(int daysAgo, int hour) =>
    DateTime(2026, 11, 16 - daysAgo, hour).millisecondsSinceEpoch;

DshSession s(String id, int updatedAt, {String? ws}) {
  final j = <String, dynamic>{
    'id': id,
    'rootId': 'r',
    'updatedAt': updatedAt,
    'running': false,
    'blank': false,
    'title': '标题 $id',
    'workspaceTitle': ?ws,
  };
  return DshSession.fromJson(j);
}

void main() {
  group('dayBucketOf', () {
    test('今天 / 昨天 / 更早', () {
      expect(dayBucketOf(ms(0, 9), now), 0);
      expect(dayBucketOf(ms(0, 0), now), 0);
      expect(dayBucketOf(ms(1, 23), now), 1);
      expect(dayBucketOf(ms(2, 0), now), 2);
      expect(dayBucketOf(ms(30, 8), now), 2);
    });

    test('边界与非法值', () {
      expect(dayBucketOf(0, now), 2);
      expect(dayBucketOf(-5, now), 2);
    });
  });

  group('workspaceLabelOf', () {
    test('空标题兜底「未分组」', () {
      expect(workspaceLabelOf(s('a', ms(0, 9))), '未分组');
      expect(workspaceLabelOf(s('a', ms(0, 9), ws: '')), '未分组');
      expect(workspaceLabelOf(s('a', ms(0, 9), ws: '手机会话')), '手机会话');
    });
  });

  group('groupSessionsByTime', () {
    test('分组顺序固定：今天 → 昨天 → 更早；空桶不产出', () {
      final groups = groupSessionsByTime([
        s('old', ms(3, 8), ws: 'ws-a'),
        s('y', ms(1, 9), ws: 'ws-a'),
        s('t2', ms(0, 11), ws: 'ws-b'),
        s('t1', ms(0, 9), ws: 'ws-a'),
      ], now: now);
      expect(groups.map((g) => g.key).toList(), ['today', 'yesterday', 'earlier']);
      expect(groups.map((g) => g.label).toList(), ['今天', '昨天', '更早']);
    });

    test('只有今天时不出昨天/更早组', () {
      final groups = groupSessionsByTime([s('t1', ms(0, 9))], now: now);
      expect(groups.length, 1);
      expect(groups[0].key, 'today');
    });

    test('桶内时间倒序（最新在前）', () {
      final groups = groupSessionsByTime([
        s('t1', ms(0, 9), ws: 'w'),
        s('t2', ms(0, 11), ws: 'w'),
        s('t3', ms(0, 10), ws: 'w'),
      ], now: now);
      expect(groups[0].rows.map((r) => r.session.id).toList(), ['t2', 't3', 't1']);
    });

    test('桶内按工作区聚簇：时间只决定小节顺序，旧会话并回同工作区小节尾部', () {
      // 时间序 a1(11) > b1(10) > a2(9) > a3(8)；a2/a3 虽比 b1 旧，
      // 也要并回 ws-a 小节尾部（小节顺序由各工作区最新会话的时间决定）。
      final groups = groupSessionsByTime([
        s('a1', ms(0, 11), ws: 'ws-a'),
        s('b1', ms(0, 10), ws: 'ws-b'),
        s('a2', ms(0, 9), ws: 'ws-a'),
        s('a3', ms(0, 8), ws: 'ws-a'),
      ], now: now);
      expect(groups[0].rows.map((r) => r.sectionLabel).toList(), ['ws-a', null, null, 'ws-b']);
      expect(groups[0].rows.map((r) => r.session.id).toList(), ['a1', 'a2', 'a3', 'b1']);
    });

    test('无工作区的会话落「未分组」小节', () {
      final groups = groupSessionsByTime([
        s('x', ms(0, 10)),
        s('y', ms(0, 9), ws: 'w'),
      ], now: now);
      expect(groups[0].rows.map((r) => r.sectionLabel).toList(), ['未分组', 'w']);
    });

    test('同一时刻按工作区名升序（二次键）', () {
      final t = ms(0, 10);
      final groups = groupSessionsByTime([
        s('z', t, ws: 'ws-z'),
        s('a', t, ws: 'ws-a'),
      ], now: now);
      expect(groups[0].rows.map((r) => r.session.id).toList(), ['a', 'z']);
    });

    test('「更早」组 collapsible 且计数正确；今天/昨天不可折叠', () {
      final groups = groupSessionsByTime([
        s('o1', ms(2, 8)),
        s('o2', ms(3, 8)),
        s('t', ms(0, 9)),
      ], now: now);
      expect(groups[0].collapsible, isFalse);
      expect(groups[1].collapsible, isTrue);
      expect(groups[1].count, 2);
    });
  });

  group('visibleRowsOf', () {
    test('「更早」收起时 0 行，展开时全量', () {
      final g = SessionGroup(
        key: 'earlier',
        label: '更早',
        rows: [SessionRow(s('o', ms(2, 8), ws: 'w'), 'w')],
        collapsible: true,
      );
      expect(visibleRowsOf(g, false), isEmpty);
      expect(visibleRowsOf(g, true).length, 1);
      final normal = SessionGroup(key: 'today', label: '今天', rows: g.rows, collapsible: false);
      expect(visibleRowsOf(normal, false).length, 1);
    });
  });
}
