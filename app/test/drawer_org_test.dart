/// 会话抽屉组织能力（置顶 / 未读 / 多选批量归档）的单测。
///
/// 纯逻辑直接 import drawer_org.dart；状态行为用假网关（不连网络）验证
/// 未读记账、批量归档逐条调用与置顶的 kernel-call 参数。
library;

import 'dart:async';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/drawer_filter_bar.dart';
import 'package:dshchat/ui/drawer_org.dart';
import 'package:flutter_test/flutter_test.dart';

DshSession _session(
  String id, {
  String? title,
  bool running = false,
  String? workspace,
  int updatedAt = 0,
  bool blank = false,
}) => DshSession(
  id: id,
  rootId: '',
  updatedAt: updatedAt,
  running: running,
  blank: blank,
  title: title,
  workspaceTitle: workspace,
);

Map<String, dynamic> _sessionJson(String id, {String? title}) => {
  'id': id,
  'rootId': '',
  'updatedAt': 0,
  'running': false,
  'blank': false,
  'title': title ?? id,
};

/// 假网关：记录 request 帧与 raw 帧，按帧类型回最小可用应答。
class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final _events = StreamController<GatewayEvent>.broadcast();
  final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
  final List<({String type, Map<String, dynamic> payload})> requests = [];
  final Set<String> archiveCalls = <String>{};

  /// 这些会话 id 的归档请求会失败（模拟部分失败）。
  Set<String> failArchive = <String>{};

  /// workspaces 应答的顶层置顶集合（故意用 Object? 便于测脏数据过滤）。
  List<Object?> pinned = <Object?>['p3', 'p1'];

  /// true 时 workspaces 应答不带 pinnedSessionIds（模拟当前桥只回 workspaces）。
  bool omitPinned = false;

  /// sessions 帧返回的活动会话。
  List<Map<String, dynamic>> sessionList = <Map<String, dynamic>>[];

  @override
  Stream<GatewayEvent> get events => _events.stream;

  @override
  Stream<GatewayState> get state => const Stream<GatewayState>.empty();

  @override
  bool sendRawFrame(Map<String, dynamic> frame) {
    frames.add(Map<String, Object?>.from(frame));
    return true;
  }

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type: type, payload: Map<String, dynamic>.from(payload)));
    switch (type) {
      case 'sessions':
        return {'sessions': sessionList};
      case 'workspaces':
        return {
          'workspaces': [
            {'id': 'w1', 'title': '工作区', 'rootId': 'r1', 'path': '/p'},
          ],
          if (!omitPinned) 'pinnedSessionIds': pinned,
        };
      case 'session-pin':
      case 'session-unpin':
        final id = payload['sessionId'] as String? ?? '';
        pinned = type == 'session-pin'
            ? [id, ...pinned.whereType<String>().where((e) => e != id)]
            : pinned.where((e) => e != id).toList();
        return {'sessionId': id, 'pinnedSessionIds': pinned};
      case 'session-archive':
        final id = payload['sessionId'] as String? ?? '';
        if (failArchive.contains(id)) {
          throw RequestException('ARCHIVE_FAILED', '模拟归档失败');
        }
        archiveCalls.add(id);
        return {'sessionId': id};
      case 'history':
        return {'events': <dynamic>[], 'hasMore': false};
      default:
        return <String, dynamic>{};
    }
  }

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) async {
    if (type == 'history') {
      return {'events': <dynamic>[], 'hasMore': false};
    }
    return request(type, payload);
  }

  void push(GatewayEvent event) => _events.add(event);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('drawerSessionVisible', () {
    final s = _session('s1', running: true, workspace: '工作区A');

    test('all 全通过；running 只看运行中', () {
      expect(
        drawerSessionVisible(
          s,
          filter: DrawerFilter.all,
          pendingIds: const {},
          unreadIds: const {},
        ),
        isTrue,
      );
      expect(
        drawerSessionVisible(
          s,
          filter: DrawerFilter.running,
          pendingIds: const {},
          unreadIds: const {},
        ),
        isTrue,
      );
      expect(
        drawerSessionVisible(
          _session('s2'),
          filter: DrawerFilter.running,
          pendingIds: const {},
          unreadIds: const {},
        ),
        isFalse,
      );
    });

    test('pending / unread 按 id 集合判定', () {
      expect(
        drawerSessionVisible(
          s,
          filter: DrawerFilter.pending,
          pendingIds: const {'s1'},
          unreadIds: const {},
        ),
        isTrue,
      );
      expect(
        drawerSessionVisible(
          s,
          filter: DrawerFilter.pending,
          pendingIds: const {},
          unreadIds: const {},
        ),
        isFalse,
      );
      expect(
        drawerSessionVisible(
          s,
          filter: DrawerFilter.unread,
          pendingIds: const {},
          unreadIds: const {'s1'},
        ),
        isTrue,
      );
      expect(
        drawerSessionVisible(
          s,
          filter: DrawerFilter.unread,
          pendingIds: const {},
          unreadIds: const {},
        ),
        isFalse,
      );
    });

    test('scope 不匹配直接不可见', () {
      expect(
        drawerSessionVisible(
          s,
          filter: DrawerFilter.all,
          pendingIds: const {},
          unreadIds: const {},
          scope: '工作区B',
        ),
        isFalse,
      );
      expect(
        drawerSessionVisible(
          s,
          filter: DrawerFilter.all,
          pendingIds: const {},
          unreadIds: const {},
          scope: '工作区A',
        ),
        isTrue,
      );
    });
  });

  group('toggledSelection', () {
    test('未选加入、已选移除，且不改原集合', () {
      const original = <String>{'s1'};
      final added = toggledSelection(original, 's2');
      expect(added, {'s1', 's2'});
      expect(original, {'s1'}, reason: '返回新集合，原集合保持');

      final removed = toggledSelection(original, 's1');
      expect(removed, isEmpty);
      expect(original, {'s1'});
    });
  });

  group('pinnedSessionsOf', () {
    test('按置顶集合顺序排，过滤已不在清单里的 id', () {
      final sessions = [_session('s1'), _session('s2'), _session('s3')];
      final pinned = pinnedSessionsOf(sessions, {'s3', 's1', 'gone'});
      expect(pinned.map((s) => s.id), ['s3', 's1']);
    });

    test('空集合返回空列表', () {
      expect(pinnedSessionsOf([_session('s1')], const {}), isEmpty);
    });
  });

  group('filterArchivedSessions', () {
    final archived = [
      _session('a1', title: '周报', workspace: '工作区A'),
      _session('a2', title: '月报', workspace: '工作区B'),
    ];

    test('搜索 + 范围 + 未读筛选叠加', () {
      expect(
        filterArchivedSessions(
          archived,
          query: '周',
          scope: null,
          filter: DrawerFilter.all,
          pendingIds: const {},
          unreadIds: const {},
        ).map((s) => s.id),
        ['a1'],
      );
      expect(
        filterArchivedSessions(
          archived,
          query: '',
          scope: '工作区B',
          filter: DrawerFilter.all,
          pendingIds: const {},
          unreadIds: const {},
        ).map((s) => s.id),
        ['a2'],
      );
      expect(
        filterArchivedSessions(
          archived,
          query: '',
          scope: null,
          filter: DrawerFilter.unread,
          pendingIds: const {},
          unreadIds: const {'a2'},
        ).map((s) => s.id),
        ['a2'],
      );
    });
  });

  group('ChatState 未读', () {
    test('标记 / 清除 / 重复标记不重复通知', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      var notifications = 0;
      state.addListener(() => notifications++);

      state.markSessionUnread('s1');
      expect(state.isSessionUnread('s1'), isTrue);
      expect(notifications, 1);

      state.markSessionUnread('s1');
      expect(notifications, 1, reason: '已标未读再标一次不该重建');

      state.clearSessionUnread('s1');
      expect(state.isSessionUnread('s1'), isFalse);
      expect(notifications, 2);

      state.clearSessionUnread('missing');
      expect(notifications, 2, reason: '没标过的 id 清除不该重建');
      state.dispose();
    });

    test('打开会话清除未读', () async {
      final gw = _FakeGateway()
        ..sessionList = [_sessionJson('s1'), _sessionJson('s2')];
      final state = ChatState(gw);
      await state.loadSessions();
      state.markSessionUnread('s1');

      final s1 = state.sessions.firstWhere((s) => s.id == 's1');
      await state.openSession(s1);
      expect(state.isSessionUnread('s1'), isFalse);
      expect(state.sessionId, 's1');
      state.dispose();
    });

    test('非当前会话回合结束/失败标未读；当前会话与 abort 不标', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.sessionId = 's1';

      gw.push(TurnEndedEvent('s2', 'stop'));
      await Future<void>.delayed(Duration.zero);
      expect(state.isSessionUnread('s2'), isTrue);

      gw.push(TurnEndedEvent('s1', 'stop'));
      await Future<void>.delayed(Duration.zero);
      expect(state.isSessionUnread('s1'), isFalse);

      gw.push(TurnEndedEvent('s3', 'aborted'));
      await Future<void>.delayed(Duration.zero);
      expect(state.isSessionUnread('s3'), isFalse);

      gw.push(TurnFailedEvent('s4', '出错了'));
      await Future<void>.delayed(Duration.zero);
      expect(state.isSessionUnread('s4'), isTrue);
      state.dispose();
    });
  });

  group('批量归档', () {
    test('逐条调用、去重、部分失败计数', () async {
      final gw = _FakeGateway()..failArchive = {'s2'};
      final state = ChatState(gw);

      final result = await state.archiveSessions(['s1', 's2', 's1', '']);
      expect(result.archived, 1);
      expect(result.failed, 1);
      expect(result.total, 2);
      expect(result.ok, isFalse);
      expect(gw.archiveCalls, {'s1'});
      final archiveRequests = gw.requests
          .where((r) => r.type == 'session-archive')
          .toList();
      expect(archiveRequests.length, 2, reason: '重复 id 只打一次');
      expect(archiveRequests.first.payload['sessionId'], 's1');
      state.dispose();
    });

    test('全部成功 ok=true，空集合不产生请求', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);

      final empty = await state.archiveSessions(const []);
      expect(empty.ok, isTrue);
      expect(gw.requests, isEmpty);

      final ok = await state.archiveSessions(['s1', 's2']);
      expect(ok.ok, isTrue);
      expect(ok.archived, 2);
      expect(gw.archiveCalls, {'s1', 's2'});
      state.dispose();
    });
  });

  group('置顶', () {
    test('pinSessionArgs 按内核 wire 包在 request 下', () {
      expect(pinSessionArgs('s1'), {
        'request': {'sessionId': 's1'},
      });
    });

    test('workspaceListing 解析顶层 pinnedSessionIds 并过滤脏值', () async {
      final gw = _FakeGateway()..pinned = ['p1', null, '', 42, 'p2'];
      final listing = await gw.workspaceListing();
      expect(listing.workspaces.single.title, '工作区');
      expect(listing.pinnedSessionIds, ['p1', 'p2']);
    });

    test('workspaceListing 字段缺席返回 null（不把读不到当成空置顶）', () async {
      final gw = _FakeGateway()..omitPinned = true;
      final listing = await gw.workspaceListing();
      expect(listing.pinnedSessionIds, isNull);
    });

    test('桥声明 session-pin-v1 时走专用帧，不碰内核调用面', () async {
      final gw = _FakeGateway()
        ..capabilities = ['session-pin-v1']
        ..pinned = <Object?>[];
      final state = ChatState(gw);

      await state.setSessionPinned('s1', true);
      expect(
        gw.requests.any(
          (r) => r.type == 'session-pin' && r.payload['sessionId'] == 's1',
        ),
        isTrue,
      );
      expect(state.pinnedSessionIds, {'s1'});

      await state.setSessionPinned('s1', false);
      expect(
        gw.requests.any(
          (r) => r.type == 'session-unpin' && r.payload['sessionId'] == 's1',
        ),
        isTrue,
      );
      expect(state.pinnedSessionIds, isEmpty);
    });

    test('setSessionPinned 发 kernel-call 并更新置顶集合', () async {
      final gw = _FakeGateway()
        ..pinned = ['s1']
        ..capabilities = ['kernel-call-v1']
        ..debugSetKernelCatalog(const [
          KernelEndpoint(
            endpoint: 'workspace/pinSession',
            scope: 'chat.write',
            summary: '置顶会话',
          ),
          KernelEndpoint(
            endpoint: 'workspace/unpinSession',
            scope: 'chat.write',
            summary: '取消置顶会话',
          ),
        ]);
      final state = ChatState(gw);

      final future = state.setSessionPinned('s1', true);
      await Future<void>.delayed(Duration.zero);
      final frame = gw.frames.firstWhere((f) => f['type'] == 'kernel-call');
      expect(frame['endpoint'], 'workspace/pinSession');
      expect(frame['args'], {
        'request': {'sessionId': 's1'},
      });
      gw.kernelCallRegistry.settle(
        frame['callId'] as String,
        KernelCallResult.ok({
          'pinnedSessionIds': ['s1'],
        }),
      );
      await future;

      expect(state.pinnedSessionIds, {'s1'});
      expect(state.isSessionPinned('s1'), isTrue);
      // 成功后还要拉一次 workspace 清单对齐（fake 记录 requests）。
      expect(
        gw.requests.where((r) => r.type == 'workspaces').length,
        greaterThanOrEqualTo(1),
      );

      // 取消置顶走另一个端点。
      gw.pinned = <Object?>[];
      final unset = state.setSessionPinned('s1', false);
      await Future<void>.delayed(Duration.zero);
      final last = gw.frames.lastWhere((f) => f['type'] == 'kernel-call');
      expect(last['endpoint'], 'workspace/unpinSession');
      gw.kernelCallRegistry.settle(
        last['callId'] as String,
        KernelCallResult.ok({'pinnedSessionIds': <Object?>[]}),
      );
      await unset;
      expect(state.pinnedSessionIds, isEmpty);
      state.dispose();
    });

    test('内核调用未启用时给可展示的原因', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      await expectLater(
        state.setSessionPinned('s1', true),
        throwsA(
          isA<RequestException>()
              .having((e) => e.code, 'code', 'NOT_SUPPORTED')
              .having((e) => e.message, 'message', contains('内核调用未启用')),
        ),
      );
      state.dispose();
    });
  });
}
