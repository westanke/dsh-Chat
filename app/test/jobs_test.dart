/// 后台任务（jobs）模型 / 控制器 / 面板的测试。
///
/// 全部走可编程 fake gateway（只覆写 request + 事件流），不碰真实网络；
/// 覆盖：模型 JSON round-trip、job-list 归组、推送状态迁移、kill 帧、
/// 重连后重拉、空列表面板、胶囊计数与语义标签。
library;

import 'dart:async';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/jobs.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/jobs_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeJobsGateway extends GatewayClient {
  _FakeJobsGateway({this.jobs = const []})
    : super(baseUrl: 'http://127.0.0.1:1');

  final List<Map<String, dynamic>> jobs;
  final List<(String, Map<String, dynamic>)> requests = [];
  final StreamController<JobPush> pushCtrl =
      StreamController<JobPush>.broadcast();
  final StreamController<GatewayState> stateCtrl =
      StreamController<GatewayState>.broadcast();

  @override
  Stream<JobPush> get jobPushes => pushCtrl.stream;

  @override
  Stream<GatewayState> get state => stateCtrl.stream;

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) => request(type, payload);

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type, payload));
    switch (type) {
      case 'job-list':
        return {'sessionId': payload['sessionId'], 'jobs': jobs};
      case 'job-output':
        return {
          'jobId': payload['jobId'],
          'output': 'step 1\nstep 2\n',
          'nextCursor': 14,
          'truncated': false,
        };
      case 'job-kill':
        return {
          'jobId': payload['jobId'],
          'killed': payload['jobId'] != 'job-done',
        };
      default:
        throw RequestException('UNKNOWN_TYPE', 'fake: $type');
    }
  }
}

Map<String, dynamic> _runningJob() => {
  'id': 'job-run',
  'kind': 'bash',
  'label': '构建 APK',
  'owner': 'lead',
  'status': 'running',
  'progress': 'downloading gradle',
  'startedAt': 1700000000000,
};

Map<String, dynamic> _finishedJob() => {
  'id': 'job-done',
  'kind': 'bash',
  'label': '跑单测',
  'status': 'completed',
  'startedAt': 1699999000000,
  'finishedAt': 1699999600000,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JobInfo JSON round-trip 保留全部协议字段', () {
    final runningRaw = _runningJob();
    final running = JobInfo.fromJson(runningRaw);
    expect(running.id, 'job-run');
    expect(running.owner, 'lead');
    expect(running.status, JobStatus.running);
    expect(running.phase, JobPhase.running);
    expect(running.progressLine, 'downloading gradle');
    expect(running.toJson(), runningRaw);

    final doneRaw = _finishedJob();
    final done = JobInfo.fromJson(doneRaw);
    expect(done.finishedAt, 1699999600000);
    expect(done.phase, JobPhase.finished);
    // 缺省键不补 null：toJson 与桥的原样 JSON 完全一致。
    expect(done.toJson(), doneRaw);
  });

  test('JobInfo 未知状态按已结束收口', () {
    final job = JobInfo.fromJson({
      'id': 'job-x',
      'kind': 'bash',
      'label': '未来任务',
      'status': 'paused',
      'startedAt': 1,
    });
    expect(job.status, JobStatus.unknown);
    expect(job.phase, JobPhase.finished);
  });

  test('JobOutput JSON round-trip', () {
    final raw = {
      'jobId': 'job-run',
      'output': 'hello\n',
      'nextCursor': 6,
      'truncated': true,
    };
    final output = JobOutput.fromJson(raw);
    expect(output.jobId, 'job-run');
    expect(output.output, 'hello\n');
    expect(output.nextCursor, 6);
    expect(output.truncated, isTrue);
    expect(output.toJson(), raw);
  });

  test('JobPush JSON round-trip（推送帧模型）', () {
    final raw = {
      'sessionId': 's1',
      'jobId': 'job-run',
      'status': 'stopping',
      'progress': 'sending SIGTERM',
    };
    final push = JobPush.fromJson(raw);
    expect(push.terminal, isFalse);
    expect(push.toJson(), raw);

    final doneRaw = {
      'sessionId': 's1',
      'jobId': 'job-run',
      'status': 'killed',
      'finishedAt': 1700000300000,
    };
    final done = JobPush.fromJson(doneRaw);
    expect(done.terminal, isTrue);
    expect(done.progress, isNull);
    expect(done.toJson(), doneRaw);
  });

  test('formatJobTime 用「今天/昨天/日期」而不是裸时间戳', () {
    final now = DateTime(2026, 11, 28, 18, 0);
    final today = DateTime(2026, 11, 28, 14, 5);
    final yesterday = DateTime(2026, 11, 27, 9, 12);
    expect(formatJobTime(today.millisecondsSinceEpoch, now: now), '今天 14:05');
    expect(
      formatJobTime(yesterday.millisecondsSinceEpoch, now: now),
      '昨天 09:12',
    );
    expect(formatJobTime(0, now: now), '');
  });

  test('拉取基线：运行中在前、已结束在后，分组正确', () async {
    final gateway = _FakeJobsGateway(jobs: [_runningJob(), _finishedJob()]);
    final controller = JobsController(gateway: gateway, sessionId: 's1');
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.isLoaded, isTrue);
    expect(controller.error, isNull);
    expect(controller.jobs.map((j) => j.id), ['job-run', 'job-done']);
    expect(controller.runningCount, 1);
    expect(controller.runningJobs.single.id, 'job-run');
    expect(controller.finishedJobs.single.id, 'job-done');
    expect(gateway.requests.single.$1, 'job-list');
    expect(gateway.requests.single.$2['sessionId'], 's1');
  });

  test('推送推进状态机：running → stopping → failed', () async {
    final gateway = _FakeJobsGateway(jobs: [_runningJob()]);
    final controller = JobsController(gateway: gateway, sessionId: 's1');
    addTearDown(controller.dispose);
    await controller.refresh();

    gateway.pushCtrl.add(
      JobPush(
        sessionId: 's1',
        jobId: 'job-run',
        status: 'stopping',
        progress: 'sending SIGTERM',
      ),
    );
    await pumpEventQueue();
    final stopping = controller.jobById('job-run')!;
    expect(stopping.status, JobStatus.stopping);
    expect(stopping.phase, JobPhase.running);
    expect(stopping.progress, 'sending SIGTERM');
    // 停止中仍占运行中计数（进程还没退出）。
    expect(controller.runningCount, 1);

    gateway.pushCtrl.add(
      JobPush(
        sessionId: 's1',
        jobId: 'job-run',
        status: 'failed',
        finishedAt: 1700000300000,
      ),
    );
    await pumpEventQueue();
    final failed = controller.jobById('job-run')!;
    expect(failed.status, JobStatus.failed);
    expect(failed.phase, JobPhase.failed);
    expect(failed.finishedAt, 1700000300000);
    // 终态清空进度行（桥的语义）。
    expect(failed.progress, isNull);
    expect(controller.runningCount, 0);
  });

  test('别会话的推送不串台', () async {
    final gateway = _FakeJobsGateway(jobs: [_runningJob()]);
    final controller = JobsController(gateway: gateway, sessionId: 's1');
    addTearDown(controller.dispose);
    await controller.refresh();

    gateway.pushCtrl.add(
      JobPush(sessionId: 's2', jobId: 'job-run', status: 'killed'),
    );
    await pumpEventQueue();
    expect(controller.jobById('job-run')!.status, JobStatus.running);
  });

  test('kill 发 job-kill 帧并本地进入停止中；已结束任务返回 false', () async {
    final gateway = _FakeJobsGateway(jobs: [_runningJob(), _finishedJob()]);
    final controller = JobsController(gateway: gateway, sessionId: 's1');
    addTearDown(controller.dispose);
    await controller.refresh();

    final killed = await controller.kill('job-run');
    expect(killed, isTrue);
    expect(gateway.requests.last.$1, 'job-kill');
    expect(gateway.requests.last.$2, {'sessionId': 's1', 'jobId': 'job-run'});
    expect(controller.jobById('job-run')!.status, JobStatus.stopping);
    expect(controller.jobById('job-run')!.phase, JobPhase.running);

    final alreadyDone = await controller.kill('job-done');
    expect(alreadyDone, isFalse);
    expect(controller.jobById('job-done')!.status, JobStatus.completed);
  });

  test('重连 ready 后自动重拉基线（桥侧推送无回放）', () async {
    final gateway = _FakeJobsGateway(jobs: [_runningJob()]);
    final controller = JobsController(gateway: gateway, sessionId: 's1');
    addTearDown(controller.dispose);

    // 建控制器时网关还没就绪：不发请求。
    expect(gateway.requests, isEmpty);
    gateway.stateCtrl.add(GatewayState.ready);
    await pumpEventQueue();

    expect(gateway.requests.where((r) => r.$1 == 'job-list'), hasLength(1));
    expect(controller.isLoaded, isTrue);
    expect(controller.runningCount, 1);
  });

  test('output 拉取任务输出（不带 cursor 时不发该键）', () async {
    final gateway = _FakeJobsGateway(jobs: [_runningJob()]);
    final controller = JobsController(gateway: gateway, sessionId: 's1');
    addTearDown(controller.dispose);
    await controller.refresh();

    final output = await controller.output('job-run');
    expect(output.output, contains('step 1'));
    final payload = gateway.requests.last.$2;
    expect(payload['sessionId'], 's1');
    expect(payload['jobId'], 'job-run');
    expect(payload.containsKey('cursor'), isFalse);
  });

  testWidgets('空列表显示空态文案', (tester) async {
    final gateway = _FakeJobsGateway();
    final controller = JobsController(gateway: gateway, sessionId: 's1');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobsSheet(
            controller: controller,
            colors: const DsColors(false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('这个会话没有后台任务'), findsOneWidget);
    expect(find.text('后台任务'), findsOneWidget);
    expect(gateway.requests.single.$1, 'job-list');
  });

}
