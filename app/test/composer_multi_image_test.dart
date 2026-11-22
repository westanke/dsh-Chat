/// 输入条多图与「+ / 文件夹」常驻的回归（2026-11-21 工单 2、5）。
///
/// 工单 5 的根因：`showAddImage: _sendKeyState != stop` 把「+」与文件夹两个
/// 按钮一起包在 `if (showAddImage)` 里，运行中空输入时整排消失。修法是按钮
/// 常驻、只在未连接时置灰。
///
/// 工单 2 的根因：`_pendingImage` 是单个字段，选第二张图会覆盖第一张。修法
/// 改成列表 + 横排 chip（可横滑，最多 6 张）。
library;

import 'dart:io';

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/composer.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _screenWidth = 360.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  var pickCount = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 临时文件放 build/ 下（已 gitignore；宪法禁 /tmp）。
    tmpDir = Directory('build/composer-multi-image-test')
      ..createSync(recursive: true);
    pickCount = 0;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/platform'), null);
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  /// 每次选图返回一个新文件名（a.png / b.png …），验证多图不被覆盖。
  Future<void> pumpComposer(WidgetTester tester, {bool streaming = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dsh/platform'),
      (method) {
        if (method.method != 'pickImage') return null;
        pickCount += 1;
        final name = 'pic_$pickCount.png';
        File('${tmpDir.path}/$name').writeAsBytesSync(<int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          ...List<int>.filled(32, 0),
        ]);
        return Future<Map<String, Object>>.value(<String, Object>{
          'path': '${tmpDir.path}/$name',
          'name': name,
          'mediaType': 'image/png',
        });
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            colors: DsColors(false),
            onSend: (_) {},
            onSendWithImages: (_, _) {},
            onCancel: () {},
            onCommand: (_) {},
            streaming: streaming,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 点「+」→ 面板 →「相册」（2026-11-22 起「+」先弹附件面板，不再直跳相册）。
  Future<void> tapAdd(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.add));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    // 面板里只该有本仓真能跑的两格。
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('相册'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  group('多图（工单 2）', () {
    testWidgets('连选两张图都留在待发送列表里', (tester) async {
      await pumpComposer(tester);
      await tapAdd(tester);
      await tapAdd(tester);

      expect(find.text('pic_1.png'), findsOneWidget);
      expect(find.text('pic_2.png'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('删掉第一张只移除它，第二张还在', (tester) async {
      await pumpComposer(tester);
      await tapAdd(tester);
      await tapAdd(tester);

      // 第一个 chip 的删除标记（Chip 内 [avatar, delete] 两个 Icon）。
      final firstChip = find.ancestor(
        of: find.text('pic_1.png'),
        matching: find.byType(Chip),
      );
      await tester.tap(
        find.descendant(of: firstChip, matching: find.byIcon(Icons.cancel)),
      );
      await tester.pumpAndSettle();

      expect(find.text('pic_1.png'), findsNothing);
      expect(find.text('pic_2.png'), findsOneWidget);
    });
  });

  group('「+」按钮常驻（工单 5；2026-11-22 起对齐 dsh-go 只留 `+`）', () {
    testWidgets('运行中空输入时按钮仍在（以前会整排消失）', (tester) async {
      await pumpComposer(tester, streaming: true);
      await tester.pump();

      expect(find.byIcon(Icons.add), findsOneWidget);
      // @ 引用入口移进「+」面板（plus_panel 的『文件』格），输入条不再挂文件夹钮。
      expect(find.byIcon(Icons.folder_open_outlined), findsNothing);

      final addRect = tester.getRect(find.byIcon(Icons.add));
      expect(addRect.right, lessThanOrEqualTo(_screenWidth));
      expect(addRect.left, greaterThanOrEqualTo(0.0));
    });

    testWidgets('未连接时按钮仍在但置灰不可点', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Composer(
              colors: DsColors(false),
              onSend: (_) {},
              onSendWithImages: (_, _) {},
              onCancel: () {},
              onCommand: (_) {},
              enabled: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
      final addButton = find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(InkResponse),
      );
      expect(addButton, findsNothing); // 禁用态不挂点击响应
    });
  });
}
