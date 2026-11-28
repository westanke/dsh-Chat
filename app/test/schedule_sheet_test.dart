/// 定时任务入口 + 面板的组件测试。
///
/// 用真 `ChatState` + 可编程 fake gateway（只覆写 `request`），
/// 覆盖：能力位缺席不渲染入口、有任务时列表渲染、点启停发 schedule-edit 帧、
/// 以及 ScheduleTask 的 JSON round-trip。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/gateway_schedule.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_header_status.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/chat_top_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGateway extends GatewayClient {
  _FakeGateway({List<String> capabilities = const [], this.tasks = const []})
    : super(baseUrl: 'http://127.0.0.1:1') {
    this.capabilities = capabilities;
  }

  final List<Map<String, dynamic>> tasks;
  final List<(String, Map<String, dynamic>)> requests = [];

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type, payload));
    switch (type) {
      case 'schedule-list':
        return {'sessionId': 's1', 'items': tasks};
      case 'schedule-view':
      case 'schedule-run':
        return {'ok': true, 'value': tasks.first};
      case 'schedule-edit':
        final request = payload['request'] as Map?;
        return {
          'ok': true,
          'value': {
            ...tasks.first,
            'id': request?['id'] ?? 'task-1',
            'status': 'paused',
          },
        };
      case 'schedule-delete':
        return {'id': 'task-1', 'deleted': true, 'sessionId': 's1'};
      case 'schedule-history':
        return {
          'id': 'task-1',
          'sessionId': 's1',
          'records': [
            {
              'scheduledAt': '2026-11-27T01:00:00.000Z',
              'deliveredAt': '2026-11-27T01:00:02.000Z',
              'messageId': 'msg-1',
              'targetSessionId': 's1',
            },
          ],
        };
      default:
        throw RequestException('UNKNOWN_TYPE', 'fake: $type');
    }
  }
}

Map<String, dynamic> _taskJson() => {
  'id': 'task-1',
  'title': '每日站会',
  'prompt': '总结昨天的进展，列出今天要做的三件事。',
  'kind': 'cron',
  'expression': '0 9 * * 1-5',
  'timeZone': 'Asia/Shanghai',
  'status': 'active',
  'scheduledAt': '2026-12-01T01:00:00.000Z',
  'updatedAt': '2026-11-27T00:00:00.000Z',
  'createdAt': '2026-11-20T00:00:00.000Z',
  'target': {'kind': 'session', 'sessionId': 's1'},
  'lastDelivery': {
    'scheduledAt': '2026-11-27T01:00:00.000Z',
    'deliveredAt': '2026-11-27T01:00:02.000Z',
    'messageId': 'msg-1',
    'targetSessionId': 's1',
  },
};

Future<void> _pumpTopBar(WidgetTester tester, ChatState state) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatTopBar(
          colors: const DsColors(false),
          title: '会话标题',
          status: const ChatHeaderStatus(ChatStatusTone.ok, '就绪'),
          state: state,
          onMenu: () {},
          onNewChat: () {},
          trailing: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('无能力位时不显示定时任务入口', (tester) async {
    final gateway = _FakeGateway(tasks: [_taskJson()]);
    final state = ChatState(gateway)..sessionId = 's1';

    await _pumpTopBar(tester, state);

    expect(find.byIcon(Icons.schedule_outlined), findsNothing);
  });

  testWidgets('有任务时列表渲染标题/规则/状态/最近结果', (tester) async {
    final gateway = _FakeGateway(
      capabilities: const [scheduleCapability],
      tasks: [_taskJson()],
    );
    final state = ChatState(gateway)..sessionId = 's1';

    await _pumpTopBar(tester, state);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.schedule_outlined));
    await tester.pumpAndSettle();

    expect(find.text('每日站会'), findsOneWidget);
    expect(find.textContaining('0 9 * * 1-5'), findsOneWidget);
    expect(find.textContaining('最近投递成功'), findsOneWidget);
    final toggle = tester.widget<Switch>(
      find.byKey(const ValueKey('schedule-toggle-task-1')),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('点启停会发 schedule-edit 帧（patch.active）', (tester) async {
    final gateway = _FakeGateway(
      capabilities: const [scheduleCapability],
      tasks: [_taskJson()],
    );
    final state = ChatState(gateway)..sessionId = 's1';

    await _pumpTopBar(tester, state);
    await tester.tap(find.byIcon(Icons.schedule_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-toggle-task-1')));
    await tester.pumpAndSettle();

    final edit = gateway.requests.singleWhere((e) => e.$1 == 'schedule-edit');
    final request = edit.$2['request'] as Map;
    expect(request['id'], 'task-1');
    expect(request['action'], 'update');
    expect((request['patch'] as Map)['active'], isFalse);
    expect(request['expectedUpdatedAt'], '2026-11-27T00:00:00.000Z');
  });

  test('ScheduleTask JSON round-trip 保留内核透传字段', () {
    final raw = _taskJson();
    final task = ScheduleTask.fromJson(raw);

    expect(task.id, 'task-1');
    expect(task.sessionId, 's1');
    expect(task.title, '每日站会');
    expect(task.enabled, isTrue);
    expect(task.ruleLabel, 'cron 0 9 * * 1-5 (Asia/Shanghai)');
    expect(task.lastRunAt, isNotNull);
    expect(task.toJson(), raw);
  });
  test('ScheduleHistoryPage JSON round-trip 保留投递记录', () {
    final raw = {
      'id': 'task-1',
      'sessionId': 's1',
      'records': [
        {
          'scheduledAt': '2026-11-27T01:00:00.000Z',
          'deliveredAt': '2026-11-27T01:00:02.000Z',
          'messageId': 'msg-1',
          'targetSessionId': 's1',
        },
      ],
      'earlierRecordsUnavailable': false,
      'nextBefore': '2026-11-26T01:00:00.000Z',
    };
    final page = ScheduleHistoryPage.fromJson(raw);
    expect(page.id, 'task-1');
    expect(page.records, hasLength(1));
    expect(page.records.single.targetSessionId, 's1');
    expect(page.nextBefore, '2026-11-26T01:00:00.000Z');
    expect(page.toJson(), raw);
  });
  testWidgets('点立即运行会发 schedule-run 帧', (tester) async {
    final gateway = _FakeGateway(
      capabilities: const [scheduleCapability],
      tasks: [_taskJson()],
    );
    final state = ChatState(gateway)..sessionId = 's1';

    await _pumpTopBar(tester, state);
    await tester.tap(find.byIcon(Icons.schedule_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即运行'));
    await tester.pumpAndSettle();

    expect(gateway.requests.any((e) => e.$1 == 'schedule-run'), isTrue);
  });

  testWidgets('点详情会拉 schedule-view 与 schedule-history', (tester) async {
    final gateway = _FakeGateway(
      capabilities: const [scheduleCapability],
      tasks: [_taskJson()],
    );
    final state = ChatState(gateway)..sessionId = 's1';

    await _pumpTopBar(tester, state);
    await tester.tap(find.byIcon(Icons.schedule_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();

    expect(find.text('运行历史'), findsOneWidget);
    expect(find.textContaining('投递到 s1'), findsOneWidget);
    expect(gateway.requests.any((e) => e.$1 == 'schedule-view'), isTrue);
    expect(gateway.requests.any((e) => e.$1 == 'schedule-history'), isTrue);
  });

  testWidgets('删除需确认，确认后发 schedule-delete 帧', (tester) async {
    final gateway = _FakeGateway(
      capabilities: const [scheduleCapability],
      tasks: [_taskJson()],
    );
    final state = ChatState(gateway)..sessionId = 's1';

    await _pumpTopBar(tester, state);
    await tester.tap(find.byIcon(Icons.schedule_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除定时任务？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    expect(gateway.requests.any((e) => e.$1 == 'schedule-delete'), isTrue);
  });
}
