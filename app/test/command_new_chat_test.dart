// 新对话里发斜杠命令（IKX5MV）：`/tunnel` 过去因为 sessionId 为空被当成
// 普通消息发给模型；现在先上屏命令卡，再 session-create，然后 command-execute，
// 且重拉历史后命令卡仍在。
import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假网关：记录帧，按 type 回假应答（不连接）。
class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<(String, Map<String, dynamic>)> requests = [];

  /// 置 true 时 session-create 直接失败，用来验「建不出来要说出来」。
  bool failCreate = false;

  @override
  void subscribe(String? sessionId) {}

  // history 走 requestWithTimeout（真正的发送要连上链路才做），这里直接转 request。
  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) =>
      request(type, payload);

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type, payload));
    switch (type) {
      case 'session-create':
        if (failCreate) {
          throw RequestException('INTERNAL', 'session-create 失败');
        }
        return <String, dynamic>{'sessionId': 'sid-new'};
      case 'command-execute':
        return <String, dynamic>{
          'result': {'kind': 'ok', 'text': 'tunnel 已切换'},
        };
      case 'sessions':
        return <String, dynamic>{'sessions': <dynamic>[], 'roots': <dynamic>[]};
      case 'history':
        return <String, dynamic>{'events': <dynamic>[], 'hasMore': false};
      default:
        throw RequestException('NOT_CONNECTED', 'fake gateway');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('新对话执行命令：先 session-create 再 command-execute，命令卡保留', () async {
    final gw = _FakeGateway();
    final state = ChatState(gw);
    // 选了目录 → 走 session-create{rootId,cwd}，不碰手机工作区 REST。
    state.setPendingLocation(
      const SessionLocation(rootId: 'root-1', cwd: 'projects/dsh', label: 'dsh'),
    );

    await state.runCommand('/tunnel');

    final types = gw.requests
        .map((r) => r.$1)
        .where((t) => t == 'session-create' || t == 'command-execute')
        .toList();
    expect(types, ['session-create', 'command-execute']);
    expect(state.sessionId, 'sid-new');
    final card = state.messages.singleWhere((m) => m.role == 'command');
    expect(card.text, '/tunnel\n✓ tunnel 已切换');
    // 执行成功后 reloadHistory 已跑过，卡不能又被冲掉（merge 的经典坑）。
    expect(state.messages.where((m) => m.role == 'command'), hasLength(1));
    expect(state.pendingLocation, isNull);
  });

  test('命令卡只属于执行它的会话：切会话/重进都不再挂着', () async {
    final gw = _FakeGateway();
    final state = ChatState(gw);
    state.setPendingLocation(
      const SessionLocation(rootId: 'root-1', cwd: 'projects/dsh', label: 'dsh'),
    );

    await state.runCommand('/tunnel');
    expect(state.messages.where((m) => m.role == 'command'), hasLength(1));

    // 切到另一个会话并拉历史：上一会话的卡片不能跟过来（真机 2026-11-23）。
    state.sessionId = 'sid-other';
    await state.reloadHistory();
    expect(state.messages.where((m) => m.role == 'command'), isEmpty);

    // 再回到原会话（重新打开）：卡片按设计消失，不会永久挂在结尾。
    state.sessionId = null;
    await state.openSession(
      const DshSession(
        id: 'sid-new',
        rootId: 'root-1',
        updatedAt: 0,
        running: false,
        blank: false,
      ),
    );
    expect(state.messages.where((m) => m.role == 'command'), isEmpty);
  });

  test('已有会话不会重复建会话', () async {
    final gw = _FakeGateway();
    final state = ChatState(gw);
    state.sessionId = 'sid-old';

    await state.runCommand('/model');

    expect(
      gw.requests.where((r) => r.$1 == 'session-create'),
      isEmpty,
    );
    expect(
      gw.requests.where((r) => r.$1 == 'command-execute').single.$2['sessionId'],
      'sid-old',
    );
  });

  test('建会话失败：命令卡标红并报错，不当正文发出', () async {
    final gw = _FakeGateway()..failCreate = true;
    final state = ChatState(gw);
    state.setPendingLocation(
      const SessionLocation(rootId: 'root-1', cwd: '', label: '根目录'),
    );

    await state.runCommand('/tunnel');

    final card = state.messages.singleWhere((m) => m.role == 'command');
    expect(card.text, contains('✗'));
    expect(state.lastError, contains('建立会话失败'));
    expect(state.sessionId, isNull);
    // 没有 message 帧：命令不会被静默降级成「发给模型」的正文。
    expect(gw.requests.where((r) => r.$1 == 'message'), isEmpty);
    expect(gw.requests.where((r) => r.$1 == 'command-execute'), isEmpty);
  });
}
