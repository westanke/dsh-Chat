// 会话轮状态兜底 + 订阅退订的单测。
//
// 背景（issue IKX5 尾帧丢失的客户端侧）：
// 1) `chat.session.status` 走 host 流，不依赖跟随流——turn/end 丢了也能收掉「生成中」；
// 2) 桥的 subscribe 是**合并**语义，`subscribe(null)` 以前直接 return → 白名单只增不减。
import 'dart:async';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/notify.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/notify_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只回放事件流、记录发出的原始帧的假网关（不连网络）。
class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final _events = StreamController<GatewayEvent>.broadcast();
  final _states = StreamController<GatewayState>.broadcast();
  final List<Map<String, Object?>> frames = <Map<String, Object?>>[];

  @override
  Stream<GatewayEvent> get events => _events.stream;

  @override
  Stream<GatewayState> get state => _states.stream;

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
    switch (type) {
      case 'history':
        return {'events': <dynamic>[], 'hasMore': false};
      default:
        return <String, dynamic>{};
    }
  }

  void push(GatewayEvent event) => _events.add(event);
}

void main() {
  group('subscriptionFrames', () {
    test('首次订阅只发 subscribe', () {
      expect(subscriptionFrames(null, 's1'), [
        {'type': 'subscribe', 'sessionId': 's1'},
      ]);
    });

    test('换会话先退订再订阅（白名单不再只增不减）', () {
      expect(subscriptionFrames('s1', 's2'), [
        {'type': 'unsubscribe'},
        {'type': 'subscribe', 'sessionId': 's2'},
      ]);
    });

    test('订阅同一会话是空操作；退订一个没订过的会话也空操作', () {
      expect(subscriptionFrames('s1', 's1'), isEmpty);
      expect(subscriptionFrames(null, null), isEmpty);
    });

    test('退订发 unsubscribe', () {
      expect(subscriptionFrames('s1', null), [
        {'type': 'unsubscribe'},
      ]);
      expect(subscriptionFrames('s1', ''), [
        {'type': 'unsubscribe'},
      ]);
    });
  });

  test('subscribe(null) 真的发出 unsubscribe 帧', () {
    final gw = _FakeGateway();
    gw.subscribe('s1');
    expect(gw.subscribedSessionId, 's1');
    gw.subscribe(null);
    expect(gw.subscribedSessionId, isNull);
    expect(gw.frames, [
      {'type': 'subscribe', 'sessionId': 's1'},
      {'type': 'unsubscribe'},
    ]);
  });

  test('chat.session.status 的 running=false 收掉「生成中」并重拉历史', () async {
    final gw = _FakeGateway();
    final state = ChatState(gw);
    state.sessionId = 's1';
    state.streaming = true;
    state.streamText = '正在生成';

    gw.push(SessionStatusEvent('s1', false));
    await Future<void>.delayed(Duration.zero);

    expect(state.streaming, isFalse);
    expect(state.streamText, isEmpty);
    state.dispose();
  });

  test('正常收尾（streaming 已落）不会被 status 再触发一次重拉', () async {
    final gw = _FakeGateway();
    final state = ChatState(gw);
    state.sessionId = 's1';
    state.streaming = false;

    gw.push(SessionStatusEvent('s1', false));
    await Future<void>.delayed(Duration.zero);

    expect(state.streaming, isFalse);
    state.dispose();
  });

  /// 通知兜底：turn.end 到了不重复发；turn.end 丢了由 status 补一条。
  testWidgets('turn.end 之后的 status 不再重复通知', (tester) async {
    final gw = _FakeGateway();
    final state = ChatState(gw);
    final sent = <NotifyPayload>[];
    final watcher = NotifyWatcher(
      state,
      statusOf: () async =>
          const NotifyStatus(native: true, permission: true, enabled: true),
      show: (payload) async {
        sent.add(payload);
        return true;
      },
    );

    gw.push(TurnEndedEvent('s1', 'done'));
    await tester.pump();
    gw.push(SessionStatusEvent('s1', false));
    await tester.pump();

    expect(sent.map((p) => p.title).toList(), ['回答已完成']);
    watcher.dispose();
    state.dispose();
  });

  testWidgets('turn.end 丢了（老桥）→ status 兜一条完成通知', (tester) async {
    final gw = _FakeGateway();
    final state = ChatState(gw);
    final sent = <NotifyPayload>[];
    final watcher = NotifyWatcher(
      state,
      statusOf: () async =>
          const NotifyStatus(native: true, permission: true, enabled: true),
      show: (payload) async {
        sent.add(payload);
        return true;
      },
    );

    gw.push(SessionStatusEvent('s1', true)); // 开轮
    gw.push(SessionStatusEvent('s1', false)); // 直接 idle，没有 turn.end
    await tester.pump();

    expect(sent.map((p) => p.title).toList(), ['回答已完成']);
    watcher.dispose();
    state.dispose();
  });
}
