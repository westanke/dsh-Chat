/// 生成文件卡更多菜单：文件操作入口的显隐与发帧参数。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_artifact_card.dart';
import 'package:dshchat/ui/turn_changes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<({String type, Map<String, dynamic> payload})> requests = [];
  RequestException? error;

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type: type, payload: Map<String, dynamic>.from(payload)));
    final e = error;
    if (e != null) throw e;
    return <String, dynamic>{'trashId': 'trash-1'};
  }

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) => request(type, payload);
}

ArtifactFile _artifact(String path) =>
    ArtifactFile(path: path, kind: ArtifactKind.markdown);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox(width: 360, child: SingleChildScrollView(child: child)),
  ),
);

ArtifactCard _card(_FakeGateway gw, {String? rootId = 'root-9'}) => ArtifactCard(
  colors: DsColors(false),
  files: [_artifact('/w/notes.md')],
  gateway: gw,
  rootId: rootId,
);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_horiz));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('两个帧都声明 → 菜单多出重命名 / 移到回收站', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()
      ..supportedFrames = const ['file-rename', 'file-delete'];

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);

    expect(find.text('打开 / 预览'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('移到回收站'), findsOneWidget);
  });

  testWidgets('只声明 file-rename → 不出现移到回收站', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()..supportedFrames = const ['file-rename'];

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('移到回收站'), findsNothing);
  });

  testWidgets('只声明 file-delete → 不出现重命名', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()..supportedFrames = const ['file-delete'];

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);

    expect(find.text('重命名'), findsNothing);
    expect(find.text('移到回收站'), findsOneWidget);
  });

  testWidgets('没声明帧 → 菜单仍是原来的三项', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway();

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);

    expect(find.text('打开 / 预览'), findsOneWidget);
    expect(find.text('复制路径'), findsOneWidget);
    expect(find.text('分享文件'), findsOneWidget);
    expect(find.text('重命名'), findsNothing);
    expect(find.text('移到回收站'), findsNothing);
  });

  testWidgets('重命名：默认原名，确认后发 file-rename（带 rootId/from/to）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()..supportedFrames = const ['file-rename'];

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, 'notes.md');

    await tester.enterText(find.byType(TextFormField), 'renamed.md');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(gw.requests.single.type, 'file-rename');
    expect(gw.requests.single.payload, {
      'rootId': 'root-9',
      'from': '/w/notes.md',
      'to': '/w/renamed.md',
    });
    expect(find.text('已重命名'), findsOneWidget);
  });

  testWidgets('重命名：rootId 拿不到就不带该字段', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()..supportedFrames = const ['file-rename'];

    await tester.pumpWidget(_host(_card(gw, rootId: null)));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'renamed.md');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(gw.requests.single.payload, {
      'from': '/w/notes.md',
      'to': '/w/renamed.md',
    });
  });

  testWidgets('重命名失败 → SnackBar 带桥的错误文案', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()
      ..supportedFrames = const ['file-rename']
      ..error = RequestException('PATH_INVALID', '路径必须是相对路径');

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'x.md');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('重命名失败：路径必须是相对路径'), findsOneWidget);
    expect(find.text('已重命名'), findsNothing);
  });

  testWidgets('移到回收站：二次确认后发 file-delete 并提示', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()..supportedFrames = const ['file-delete'];

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('移到回收站'));
    await tester.pumpAndSettle();

    expect(find.text('移到回收站？'), findsOneWidget);
    expect(gw.requests, isEmpty);

    await tester.tap(find.text('移到回收站'));
    await tester.pumpAndSettle();

    expect(gw.requests.single.type, 'file-delete');
    expect(gw.requests.single.payload, {
      'rootId': 'root-9',
      'path': '/w/notes.md',
    });
    expect(find.text('已移入回收站'), findsOneWidget);
  });

  testWidgets('移到回收站：取消确认则不发帧', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()..supportedFrames = const ['file-delete'];

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('移到回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(gw.requests, isEmpty);
    expect(find.text('已移入回收站'), findsNothing);
  });

  testWidgets('删除失败 → SnackBar 带错误，不误报成功', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final gw = _FakeGateway()
      ..supportedFrames = const ['file-delete']
      ..error = RequestException('SCOPE_DENIED', '缺少 files.delete 权限');

    await tester.pumpWidget(_host(_card(gw)));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('移到回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移到回收站'));
    await tester.pumpAndSettle();

    expect(find.text('移到回收站失败：缺少 files.delete 权限'), findsOneWidget);
    expect(find.text('已移入回收站'), findsNothing);
  });
}
