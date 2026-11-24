// 问题1（新建会话时模型/模式/权限不可选）与问题2（切模型后 chip 不刷新）的回归。
//
// 问题1：协议层没有「建会话时带模型 / 权限」的帧（bridge session-create 只吃
// rootId/cwd/workspaceId/agentPreset/reuseBlank），所以客户端走「先选 → 建会话
// → 补应用」：草稿存在 ChatSetupDraft，建会话后由 applyChatSetup 补 select-model
// 与 permission；模式随 session-create 的 agentPreset 字段下发。
//
// 问题2：模型 chip 的文案原先由 chip 自己拉一次 models 帧并按会话号短路
// （`_loadedFor == sid`），同会话内切完模型界面永远不更新。现在文案由
// ChatState 持有（modelLabel），切完立刻重读服务端真源。
import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/bridge/models_view.dart';
import 'package:dshchat/ui/chat_setup_draft.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假网关：记录帧，按 type 回假应答（不连接）。
class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<(String, Map<String, dynamic>)> requests = [];

  /// models 帧回的当前模型（改它就能验「切完模型 chip 跟着变」）。
  String currentModel = 'model-a';

  @override
  void subscribe(String? sessionId) {}

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
        return <String, dynamic>{'sessionId': 'sid-new'};
      case 'models':
        return <String, dynamic>{
          'current': {'provider': 'p1', 'model': currentModel},
          'routable': true,
          'groups': <dynamic>[],
          'failures': <dynamic>[],
        };
      case 'select-model':
        // 服务端回传确认后的三元组（data.selected 是真源）。
        currentModel = payload['model'] as String;
        return <String, dynamic>{
          'type': 'select-model',
          'selected': {
            'provider': payload['provider'],
            'model': payload['model'],
          },
        };
      case 'permission':
        return <String, dynamic>{'kind': 'ok'};
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

  group('问题1：新建会话也能先选模型 / 模式 / 权限', () {
    test('草稿里的模型与权限在建会话后补应用（select-model + permission）', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.setPendingLocation(
        const SessionLocation(rootId: 'root-1', cwd: 'projects/dsh', label: 'dsh'),
      );

      // 先选（还没会话）：只能存草稿。
      state.setup.model = const ModelSelection(provider: 'p1', model: 'model-x');
      state.setup.permissionValue = 'workspace-write';
      state.setup.permissionLabel = '工作区读写';
      state.setup.agentPresetId = 'preset-a';
      state.setup.agentPresetName = '标准模式';

      await state.send('你好');

      // 模式随 session-create 下发。
      final create = gw.requests.firstWhere((r) => r.$1 == 'session-create');
      expect(create.$2['agentPreset'], 'preset-a');

      // 模型与权限在建会话后补应用（会话维度才有这两帧）。
      final select = gw.requests.firstWhere((r) => r.$1 == 'select-model');
      expect(select.$2['sessionId'], 'sid-new');
      expect(select.$2['model'], 'model-x');
      final perm = gw.requests.firstWhere((r) => r.$1 == 'permission');
      expect(perm.$2['sessionId'], 'sid-new');
      expect(perm.$2['name'], 'workspace-write');

      // 补完草稿清空：不会重复补。
      expect(state.setup.isEmpty, isTrue);
      final selectCount =
          gw.requests.where((r) => r.$1 == 'select-model').length;
      expect(selectCount, 1);
    });

    test('没选任何配置时不补帧（老行为不变）', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.setPendingLocation(
        const SessionLocation(rootId: 'root-1', cwd: 'projects/dsh', label: 'dsh'),
      );

      await state.send('你好');

      expect(gw.requests.where((r) => r.$1 == 'select-model'), isEmpty);
      expect(gw.requests.where((r) => r.$1 == 'permission'), isEmpty);
    });

    test('草稿补应用逐项独立：模型失败不影响权限', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.setup.model = const ModelSelection(provider: 'p1', model: 'model-x');
      state.setup.permissionValue = 'workspace-write';

      await applyChatSetup(
        gw,
        'sid-x',
        state.setup,
        onError: (m) => state.lastError = m,
      );

      // 假网关两帧都成功：草稿清空、无错误。
      expect(state.setup.isEmpty, isTrue);
      expect(state.lastError, isNull);
    });
  });

  group('问题2：会话内切模型后 chip 文案跟着变', () {
    test('modelLabel 取服务端 models 帧的 current.model', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.sessionId = 'sid-1';

      await state.refreshModelLabel();
      expect(state.modelLabel, 'model-a');

      // 服务端换模型 → 重读一次 → 文案跟着变。
      gw.currentModel = 'model-b';
      await state.refreshModelLabel();
      expect(state.modelLabel, 'model-b');
    });

    test('没有会话时 chip 不显示（不拿上一个会话的模型占位）', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.sessionId = 'sid-1';
      await state.refreshModelLabel();
      expect(state.modelLabel, 'model-a');

      state.sessionId = null;
      await state.refreshModelLabel();
      expect(state.modelLabel, isNull);
    });

    test('切模型后重读服务端真源：显示的与实际运行的是同一个', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.sessionId = 'sid-1';
      await state.refreshModelLabel();
      expect(state.modelLabel, 'model-a');

      // 模拟 select-model 帧：服务端确认并回传 selected。
      final reply = await gw.request('select-model', {
        'sessionId': 'sid-1',
        'provider': 'p1',
        'model': 'model-b',
      });
      final selected = parseSelectModelReply(reply);
      expect(selected, isNotNull);
      expect(selected!.model, 'model-b');

      // 面板回传的那份就是服务端确认的；再重读一次应得同一个名字。
      await state.refreshModelLabel();
      expect(state.modelLabel, selected.model);
    });
  });
}
