// 新建会话可选工作目录（2026-11-15 反馈）：
// 模型解析（DshSession.cwd / DshDirectoryPage）、send() 建会话通道分流、
// 目录选择 sheet 的候选去重与浏览交互。
import 'package:dshchat/bridge/gateway.dart'; // GatewayClient / RequestException
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/session_location_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录 request 入参的假网关（不连接）。注意：createSessionAt 是
/// extension 方法（静态分派），覆写它无效；所以覆写类本体的 request，
/// 按 type 发回假应答——顺带覆盖「extension → request」完整链路。
class RecordingGateway extends GatewayClient {
  RecordingGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<(String, Map<String, dynamic>)> requests = [];

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type, payload));
    if (type == 'session-create') {
      return <String, dynamic>{'sessionId': 'sid-at-dir'};
    }
    // 其余（message 帧等）按未连接处理：立刻失败，不挂起测试。
    throw RequestException('NOT_CONNECTED', 'fake gateway');
  }
}

DshSession _session(String id, {String cwd = '', String? cwdAbsolute}) =>
    DshSession(
      id: id,
      rootId: 'root-1',
      updatedAt: 1700000000000,
      running: false,
      blank: false,
      cwd: cwd,
      cwdAbsolute: cwdAbsolute,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DshSession.cwd 解析（WirePath 相对路径）', () {
    test('fromJson 读取 cwd，缺省空串 = 会话目录就是根', () {
      final s = DshSession.fromJson({
        'id': 's1',
        'rootId': 'r1',
        'updatedAt': 1,
        'running': false,
        'blank': false,
        'cwd': 'src/app',
      });
      expect(s.cwd, 'src/app');
      final s2 = DshSession.fromJson({
        'id': 's2',
        'rootId': 'r1',
        'updatedAt': 1,
        'running': false,
        'blank': false,
      });
      expect(s2.cwd, '');
    });
  });

  group('DshDirectoryPage.fromJson（file-list 应答）', () {
    test('解析 rootId/path/entries/nextCursor', () {
      final page = DshDirectoryPage.fromJson({
        'rootId': 'r1',
        'path': 'a/b',
        'entries': [
          {'name': 'c', 'path': 'a/b/c', 'kind': 'directory'},
          {'name': 'f.ts', 'path': 'a/b/f.ts', 'kind': 'file'},
        ],
        'nextCursor': 'cur-2',
      });
      expect(page.rootId, 'r1');
      expect(page.path, 'a/b');
      expect(page.nextCursor, 'cur-2');
      expect(page.entries.length, 2);
      expect(page.entries[0].kind, 'directory');
      expect(page.entries[1].kind, 'file');
    });
  });

  group('send() 建会话通道分流', () {
    test('选了 pendingLocation：走 session-create{rootId,cwd} 并清待定', () async {
      final gw = RecordingGateway();
      final state = ChatState(gw);
      state.sessions = [_session('old', cwd: 'projects/dsh')];
      state.setPendingLocation(
        const SessionLocation(rootId: 'root-9', cwd: 'projects/dsh', label: 'x'),
      );

      await state.send('你好');

      final created = gw.requests
          .where((r) => r.$1 == 'session-create')
          .toList();
      expect(created, hasLength(1));
      expect(created.single.$2['rootId'], 'root-9');
      expect(created.single.$2['cwd'], 'projects/dsh');
      expect(state.pendingLocation, isNull); // 目录已定死
      expect(state.sessionId, 'sid-at-dir'); // 预建会话已挂上
    });

    test('未选目录：不走 session-create 目录通道', () async {
      final gw = RecordingGateway();
      final state = ChatState(gw);
      expect(state.pendingLocation, isNull);

      await state.send('你好');

      expect(
        gw.requests.where((r) => r.$1 == 'session-create'),
        isEmpty,
      ); // 分流没有落到目录通道（走原手机工作区路径，REST 不经 WS 帧）
    });

    test('newChat() 清空待定目录（不沿用上次选择）', () async {
      final gw = RecordingGateway();
      final state = ChatState(gw);
      state.setPendingLocation(
        const SessionLocation(rootId: null, cwd: '', label: '根目录'),
      );
      expect(state.pendingLocation, isNotNull);

      await state.newChat();
      expect(state.pendingLocation, isNull);
    });

    test('newChat() 清掉上一会话的生成中标记与流式缓冲', () async {
      final state = ChatState(RecordingGateway());
      state.streaming = true;
      state.streamText = '写了一半';
      await state.newChat();
      expect(state.streaming, isFalse);
      expect(state.streamText, isEmpty);
    });
  });

  group('sheet：候选去重 / 默认项 / 浏览选定', () {
    Future<void> openSheet(
      WidgetTester tester, {
      required ChatState state,
      DirectoryLister? lister,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showSessionLocationSheet(
                    context,
                    state,
                    DsColors(false),
                    lister: lister,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('默认项高亮 + 最近目录去重显示，选中后写回 state', (tester) async {
      final gw = GatewayClient(baseUrl: 'http://127.0.0.1:1');
      final state = ChatState(gw);
      state.sessions = [
        _session('a', cwd: 'work/x', cwdAbsolute: '/root/work/x'),
        _session('b', cwd: 'work/x'), // 与 a 同根同目录：去重
        _session('c', cwd: ''), // 根目录
      ];

      await openSheet(tester, state: state);

      expect(find.text('手机会话（默认）'), findsOneWidget);
      expect(find.text('根目录'), findsOneWidget);
      expect(find.text('work/x'), findsOneWidget); // 去重后只一条
      expect(find.text('/root/work/x'), findsOneWidget); // 绝对路径副标题

      await tester.tap(find.text('work/x'));
      await tester.pumpAndSettle();
      expect(state.pendingLocation?.cwd, 'work/x');
      expect(state.pendingLocation?.rootId, 'root-1');
    });

    testWidgets('已选目录后 sheet 顶部高亮显示该目录', (tester) async {
      final gw = GatewayClient(baseUrl: 'http://127.0.0.1:1');
      final state = ChatState(gw);
      state.setPendingLocation(
        const SessionLocation(rootId: 'r', cwd: 'deep/dir', label: 'deep/dir'),
      );

      await openSheet(tester, state: state);

      expect(find.text('deep/dir'), findsOneWidget);
      expect(find.text('当前选择'), findsOneWidget);
      expect(find.text('点此恢复默认'), findsOneWidget);
    });

    testWidgets('浏览：进入子目录后「在此目录新建会话」回传相对路径', (tester) async {
      final gw = GatewayClient(baseUrl: 'http://127.0.0.1:1');
      final state = ChatState(gw);
      var listedPath = '';
      await openSheet(
        tester,
        state: state,
        lister: ({String? rootId, String path = '', String? cursor}) async {
          listedPath = path;
          return DshDirectoryPage(
            rootId: rootId ?? 'r-default',
            path: path,
            nextCursor: null,
            entries: path.isEmpty
                ? [
                    const DshFileEntry(
                      name: 'src',
                      path: 'src',
                      kind: 'directory',
                    ),
                    const DshFileEntry(
                      name: 'note.md',
                      path: 'note.md',
                      kind: 'file',
                    ),
                  ]
                : [
                    const DshFileEntry(
                      name: 'inner',
                      path: 'src/inner',
                      kind: 'directory',
                    ),
                  ],
          );
        },
      );

      await tester.tap(find.text('浏览授权根目录…'));
      await tester.pumpAndSettle();
      expect(listedPath, ''); // 初次列根目录
      expect(find.text('src'), findsOneWidget);
      expect(find.text('note.md'), findsNothing); // 浏览器只列目录

      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(listedPath, 'src');
      expect(find.text('inner'), findsOneWidget);

      await tester.tap(find.text('在此目录新建会话'));
      await tester.pumpAndSettle();
      expect(state.pendingLocation?.cwd, 'src');
      expect(state.pendingLocation?.rootId, 'r-default');
      expect(state.pendingLocation?.label, 'src');
    });
  });
}
