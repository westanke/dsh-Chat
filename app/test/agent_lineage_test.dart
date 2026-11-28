/// 子代理谱系的纯投影测试：树构建/防环/容错 + 底部面板渲染与点击。
library;

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/agent_lineage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _colors = DsColors(false);

Map<String, dynamic> _projections(List<Map<String, dynamic>> catalog) => {
      'values': {'subagentCatalog': catalog},
    };

AgentLineage _lineage(List<Map<String, dynamic>> catalog) =>
    AgentLineage.fromProjections(_projections(catalog));

void main() {
  test('按 parentId 还原层级、rootId 与 depth', () {
    final lineage = _lineage([
      {'id': 'root', 'title': '负责人', 'status': 'running'},
      {
        'id': 'child',
        'parentId': 'root',
        'title': '调研',
        'status': 'completed',
        'durationMs': 65000,
      },
      {
        'id': 'grand',
        'parentId': 'child',
        'title': '取样',
        'status': 'failed',
        'lastActivity': '正在调用工具',
      },
    ]);

    expect(lineage.total, 3);
    expect(lineage.roots, hasLength(1));
    final root = lineage.roots.single;
    expect(root.id, 'root');
    expect(root.depth, 0);
    expect(root.rootId, 'root');
    expect(root.children.single.id, 'child');

    final child = root.children.single;
    expect(child.depth, 1);
    expect(child.rootId, 'root');
    expect(child.parentId, 'root');
    expect(child.children.single.id, 'grand');

    final grand = child.children.single;
    expect(grand.depth, 2);
    expect(grand.rootId, 'root');
    expect(grand.status, AgentLineageStatus.failed);
    expect(grand.lastActivity, '正在调用工具');

    expect(
      lineage.nodes.map((n) => n.id).toList(),
      ['root', 'child', 'grand'],
    );
  });

  test('多个 root 各自成树并保持投影顺序', () {
    final lineage = _lineage([
      {'id': 'a', 'title': 'A'},
      {'id': 'a1', 'parentId': 'a', 'title': 'A1'},
      {'id': 'b', 'title': 'B'},
      {'id': 'b1', 'parentId': 'b', 'title': 'B1'},
    ]);

    expect(lineage.total, 4);
    expect(lineage.roots.map((n) => n.id), ['a', 'b']);
    expect(lineage.roots[0].children.single.id, 'a1');
    expect(lineage.roots[1].children.single.id, 'b1');
    expect(lineage.nodes.map((n) => n.id), ['a', 'a1', 'b', 'b1']);
    expect(lineage.roots[0].rootId, 'a');
    expect(lineage.roots[1].rootId, 'b');
  });

  test('缺 parent / parent 不存在 / 自指都按 root 处理', () {
    final lineage = _lineage([
      {'id': 'x', 'sessionId': 'x', 'parentId': 'missing'},
      {'id': 'y', 'parent': 'y'},
      {'id': 'z'},
    ]);

    expect(lineage.total, 3);
    expect(lineage.roots.map((n) => n.id), ['x', 'y', 'z']);
    for (final root in lineage.roots) {
      expect(root.depth, 0);
      expect(root.rootId, root.id);
      expect(root.parentId, isEmpty);
      expect(root.children, isEmpty);
    }
  });

  test('父子成环时断开父边，遍历终止且不丢节点', () {
    final lineage = _lineage([
      {'id': 'a', 'parentId': 'b'},
      {'id': 'b', 'parentId': 'a'},
      {'id': 'c', 'parentId': 'a'},
    ]);

    expect(lineage.total, 3);
    expect(lineage.roots, hasLength(1));
    expect(lineage.roots.single.id, 'a');
    expect(lineage.nodes.map((n) => n.id).toList(), hasLength(3));
    expect(lineage.nodes.map((n) => n.id).toSet(), {'a', 'b', 'c'});
    expect(lineage.roots.single.children, hasLength(2));
    for (final node in lineage.nodes) {
      expect(node.rootId, 'a');
    }
  });

  test('投影缺席 / 非数组 / 空目录 / 空 id 都得到空谱系', () {
    expect(AgentLineage.fromProjections(null).isEmpty, isTrue);
    expect(AgentLineage.fromProjections(const {}).isEmpty, isTrue);
    expect(
      AgentLineage.fromProjections(const {
        'values': <String, dynamic>{},
      }).isEmpty,
      isTrue,
    );
    expect(
      AgentLineage.fromProjections(const {
        'values': {'subagentCatalog': 'nope'},
      }).isEmpty,
      isTrue,
    );
    expect(AgentLineage.fromCatalog(const []).isEmpty, isTrue);
    expect(
      _lineage([
        {'id': '   ', 'title': '无 id'},
      ]).isEmpty,
      isTrue,
    );
  });

  test('status / title / agentName / id 别名容错', () {
    final lineage = _lineage([
      {
        'id': 'root',
        'label': '父会话',
        'name': 'alpha',
        'phase': 'active',
      },
      {
        'sessionId': 'child',
        'parentSessionId': 'root',
        'title': '子任务',
        'agentName': 'beta',
        'status': 'done',
      },
      {'id': 'boom', 'parentId': 'root', 'status': 'kaboom'},
      {'id': 'quiet', 'parentId': 'root'},
    ]);

    expect(lineage.total, 4);
    final root = lineage.roots.single;
    expect(root.id, 'root');
    expect(root.title, '父会话');
    expect(root.agentName, 'alpha');
    expect(root.status, AgentLineageStatus.running);

    final child = root.children.first;
    expect(child.id, 'child');
    expect(child.parentId, 'root');
    expect(child.title, '子任务');
    expect(child.agentName, 'beta');
    expect(child.status, AgentLineageStatus.completed);

    final boom = root.children[1];
    expect(boom.status, AgentLineageStatus.idle);
    expect(boom.displayName, '子会话 boom');
    expect(root.children.last.status, AgentLineageStatus.idle);
  });

  test('耗时与最近活动格式化', () {
    final now = DateTime(2026, 11, 28, 12);
    expect(formatAgentLineageDuration(0), '0 秒');
    expect(formatAgentLineageDuration(500), '500 毫秒');
    expect(formatAgentLineageDuration(4200), '4 秒');
    expect(formatAgentLineageDuration(65000), '1 分 5 秒');
    expect(formatAgentLineageDuration(3600000), '1 小时');
    expect(formatAgentLineageAgo(now.millisecondsSinceEpoch - 15000,
        now: now), '刚刚');
    expect(
      formatAgentLineageAgo(
        now.millisecondsSinceEpoch - 2 * 60 * 1000,
        now: now,
      ),
      '2 分钟前',
    );
    expect(
      formatAgentLineageAgo(
        now.millisecondsSinceEpoch - 3 * 3600 * 1000,
        now: now,
      ),
      '3 小时前',
    );
  });

  testWidgets('空态显示标题、0 个与明确提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentLineageSheet(
            lineage: AgentLineage.empty,
            colors: _colors,
          ),
        ),
      ),
    );

    expect(find.text('子代理'), findsOneWidget);
    expect(find.text('共 0 个'), findsOneWidget);
    expect(find.text('这个会话还没有子代理'), findsOneWidget);
  });

  testWidgets('标题显示总数，点节点触发打开回调并带出历史页参数', (tester) async {
    final lineage = _lineage([
      {'id': 'root', 'title': '负责人', 'status': 'running'},
      {
        'id': 'child',
        'parentId': 'root',
        'title': '调研',
        'agentName': 'researcher',
        'status': 'completed',
        'durationMs': 65000,
        'lastActivity': '正在调用工具',
      },
      {'id': 'grand', 'parentId': 'child', 'title': '取样', 'status': 'failed'},
    ]);
    AgentLineageNode? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentLineageSheet(
            lineage: lineage,
            colors: _colors,
            onOpen: (node) => opened = node,
          ),
        ),
      ),
    );

    expect(find.text('共 3 个'), findsOneWidget);
    expect(find.text('调研'), findsOneWidget);
    expect(find.text('researcher'), findsOneWidget);
    expect(find.textContaining('耗时 1 分 5 秒'), findsOneWidget);
    expect(find.textContaining('最近：正在调用工具'), findsOneWidget);
    expect(find.text('运行中'), findsOneWidget);

    await tester.tap(find.text('调研'));
    await tester.pump();

    expect(opened, isNotNull);
    expect(opened!.id, 'child');
    final row = opened!.toSubagentRow();
    expect(row.id, 'child');
    expect(row.mode, 'unknown');
    expect(row.label, '调研');
  });
}
