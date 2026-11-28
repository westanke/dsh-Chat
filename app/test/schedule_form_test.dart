/// 定时任务表单：wire 构造 + 组件提交。
///
/// 覆盖：
/// - `ScheduleTiming` 五种规则 → 内核 timing 的字段形状；
/// - 从已有任务反推表单初值（cron / weekly / every / at）；
/// - 新建表单提交后发 `schedule-create`，编辑表单发 `schedule-edit`；
/// - 标题/指令为空时不上屏。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/gateway_schedule.dart';
import 'package:dshchat/bridge/schedule_timing.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/schedule_form.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<(String, Map<String, dynamic>)> requests = [];

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type, payload));
    switch (type) {
      case 'schedule-create':
      case 'schedule-edit':
        return {
          'ok': true,
          'value': {
            'id': 'new-task',
            'kind': 'daily',
            'title': '新任务',
            'prompt': '内容',
            'time': '09:00:00.000',
            'timeZone': 'UTC',
            'status': 'active',
            'scheduledAt': '2026-12-01T01:00:00.000Z',
            'target': {'kind': 'session', 'sessionId': 's1'},
          },
        };
      default:
        throw RequestException('UNKNOWN_TYPE', 'fake: $type');
    }
  }
}

Map<String, dynamic> _taskJson({
  String kind = 'cron',
  Map<String, dynamic> extra = const {},
}) => {
  'id': 'task-1',
  'title': '每日站会',
  'prompt': '总结昨天的进展。',
  'kind': kind,
  'status': 'active',
  'updatedAt': '2026-11-27T00:00:00.000Z',
  'target': {'kind': 'session', 'sessionId': 's1'},
  ...extra,
};

Future<void> _openForm(
  WidgetTester tester,
  ChatState state, {
  ScheduleTask? task,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showScheduleForm(
                context,
                state,
                const DsColors(false),
                task: task,
              ),
              child: const Text('打开表单'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开表单'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('daily timing 产出 time/time_zone', () {
    const timing = ScheduleTiming(
      repeat: ScheduleRepeat.daily,
      hour: 9,
      minute: 5,
    );
    expect(timing.toWire('Asia/Shanghai'), {
      'kind': 'daily',
      'daily': {'time': '09:05:00', 'time_zone': 'Asia/Shanghai'},
    });
    expect(timing.validate(), isNull);
  });

  test('weekly timing 的星期几升序去重', () {
    const timing = ScheduleTiming(
      repeat: ScheduleRepeat.weekly,
      hour: 8,
      weekdays: [5, 1, 5],
    );
    expect(timing.toWire('UTC'), {
      'kind': 'weekly',
      'weekly': {
        'time': '08:00:00',
        'time_zone': 'UTC',
        'weekdays': [1, 5],
      },
    });
  });

  test('every/cron/at 的 wire 形状', () {
    expect(
      const ScheduleTiming(repeat: ScheduleRepeat.every, everyMinutes: 30)
          .toWire('UTC'),
      {'kind': 'every', 'every_seconds': 1800},
    );
    expect(
      const ScheduleTiming(repeat: ScheduleRepeat.cron, cron: '0 9 * * *')
          .toWire('Asia/Shanghai'),
      {
        'kind': 'cron',
        'cron': {'expression': '0 9 * * *', 'time_zone': 'Asia/Shanghai'},
      },
    );
    expect(
      ScheduleTiming(
        repeat: ScheduleRepeat.at,
        hour: 18,
        minute: 30,
        date: DateTime(2026, 12, 1),
      ).toWire('UTC'),
      {
        'kind': 'at',
        'at': {
          'date': '2026-12-01',
          'time': '18:30:00',
          'time_zone': 'UTC',
        },
      },
    );
  });

  test('cron 段数与 weekly 空星期会被校验拦下', () {
    expect(
      const ScheduleTiming(repeat: ScheduleRepeat.cron, cron: '0 9 *').validate(),
      isNotNull,
    );
    expect(
      const ScheduleTiming(repeat: ScheduleRepeat.weekly).validate(),
      isNotNull,
    );
    expect(
      const ScheduleTiming(repeat: ScheduleRepeat.every, everyMinutes: 0)
          .validate(),
      isNotNull,
    );
  });

  test('fromTask 反推 cron/weekly/every', () {
    final cron = ScheduleTask.fromJson(
      _taskJson(extra: {'expression': '0 9 * * 1-5'}),
    );
    expect(ScheduleTiming.fromTask(cron).repeat, ScheduleRepeat.cron);
    expect(ScheduleTiming.fromTask(cron).cron, '0 9 * * 1-5');

    final weekly = ScheduleTask.fromJson(
      _taskJson(
        kind: 'weekly',
        extra: {'time': '08:30:00.000', 'weekdays': [3, 1]},
      ),
    );
    final w = ScheduleTiming.fromTask(weekly);
    expect(w.repeat, ScheduleRepeat.weekly);
    expect(w.hour, 8);
    expect(w.minute, 30);
    expect(w.weekdays, [1, 3]);

    final every = ScheduleTask.fromJson(
      _taskJson(kind: 'every', extra: {'everySeconds': 7200}),
    );
    expect(ScheduleTiming.fromTask(every).everyMinutes, 120);
  });

  test('create request 带 target.sessionId 与 timing', () {
    final request = buildScheduleCreateRequest(
      title: ' 日报 ',
      prompt: ' 总结 ',
      sessionId: 's1',
      timing: const ScheduleTiming(repeat: ScheduleRepeat.daily),
      timeZone: 'Asia/Shanghai',
    );
    expect(request['title'], '日报');
    expect(request['prompt'], '总结');
    expect((request['target'] as Map)['sessionId'], 's1');
    expect((request['timing'] as Map)['kind'], 'daily');
  });

  testWidgets('新建表单提交发 schedule-create', (tester) async {
    final gateway = _FakeGateway();
    final state = ChatState(gateway)..sessionId = 's1';
    await _openForm(tester, state);

    await tester.enterText(
      find.byKey(const ValueKey('schedule-form-title')),
      '每日站会',
    );
    await tester.enterText(
      find.byKey(const ValueKey('schedule-form-prompt')),
      '总结昨天的进展。',
    );
    await tester.tap(find.byKey(const ValueKey('schedule-form-submit')));
    await tester.pumpAndSettle();

    final create = gateway.requests.singleWhere((e) => e.$1 == 'schedule-create');
    final request = create.$2['request'] as Map;
    expect(request['title'], '每日站会');
    expect((request['timing'] as Map)['kind'], 'daily');
    expect((request['target'] as Map)['sessionId'], 's1');
    expect(find.byKey(const ValueKey('schedule-form-title')), findsNothing);
  });

  testWidgets('编辑表单提交发 schedule-edit 且带 expectedUpdatedAt', (tester) async {
    final gateway = _FakeGateway();
    final state = ChatState(gateway)..sessionId = 's1';
    await _openForm(
      tester,
      state,
      task: ScheduleTask.fromJson(
        _taskJson(extra: {'expression': '0 9 * * *'}),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('schedule-form-submit')));
    await tester.pumpAndSettle();

    final edit = gateway.requests.singleWhere((e) => e.$1 == 'schedule-edit');
    final request = edit.$2['request'] as Map;
    expect(request['id'], 'task-1');
    expect(request['action'], 'update');
    expect(request['expectedUpdatedAt'], '2026-11-27T00:00:00.000Z');
    expect((request['patch'] as Map)['timing'], isNotNull);
  });

  testWidgets('标题为空时显示错误且不发帧', (tester) async {
    final gateway = _FakeGateway();
    final state = ChatState(gateway)..sessionId = 's1';
    await _openForm(tester, state);

    await tester.tap(find.byKey(const ValueKey('schedule-form-submit')));
    await tester.pumpAndSettle();

    expect(find.text('标题不能为空'), findsOneWidget);
    expect(gateway.requests, isEmpty);
  });
}
