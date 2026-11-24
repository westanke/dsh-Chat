/// 「+」附件面板的回归（2026-11-22，对齐 dsh-Go plus panel）。
///
/// 守住两条：
/// 1. **不做假按钮**——只列本仓真能跑的格子（相册 / 文件）；dsh-Go 的拍照、
///    生成、语音通话、手机操控·确认方式本仓没有对应能力，一个都不许出现；
/// 2. 卡片接线真实：`计划模式` → `runCommand('/plan')` / `'/plan off'`，
///    `文件` → 输入条既有的 `@` 提及插入。
library;

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/composer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 装上输入条并点开「+」面板。
  Future<void> openPanel(
    WidgetTester tester, {
    List<String>? commands,
    String? sessionId = 'sess-1',
  }) async {
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
            onCommand: (line) => commands?.add(line),
            sessionId: sessionId,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }

  testWidgets('只列本仓真有的格子，没能力的整格/整块不出现', (tester) async {
    await openPanel(tester);

    // 真能跑的两格 + 「本对话」卡片。
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('本对话'), findsOneWidget);
    // 「权限」两处：输入条上的档位 chip + 面板「本对话」卡片的第一行。
    expect(find.text('权限'), findsWidgets);
    expect(find.text('计划模式'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    // dsh-Go 有、本仓没有能力的：一律不出现（不做假按钮）。
    expect(find.text('拍照'), findsNothing);
    expect(find.text('生成'), findsNothing);
    expect(find.text('语音通话'), findsNothing);
    expect(find.text('手机操控'), findsNothing);
    expect(find.text('确认方式'), findsNothing);
  });

  testWidgets('计划模式开关发 /plan 与 /plan off', (tester) async {
    final commands = <String>[];
    await openPanel(tester, commands: commands);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(commands, ['/plan']);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(commands, ['/plan', '/plan off']);
  });

  testWidgets('未打开会话时计划模式开关不发命令（改为存草稿，问题1）', (tester) async {
    final commands = <String>[];
    await openPanel(tester, commands: commands, sessionId: null);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    // 没有会话时 /plan 发不出去（命令帧要会话号）：不发命令。
    expect(commands, isEmpty);
  });

  testWidgets('未打开会话时计划模式开关交给上层存草稿（问题1）', (tester) async {
    final pending = <bool>[];
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
            onCommand: (line) {},
            // 还没有会话（sessionId 为 null）。
            sessionId: null,
            pendingPlan: false,
            onPendingPlan: (on) => pending.add(on),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // 开关现在可点：选择先存草稿，建会话后补发 /plan。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(pending, [true]);
  });

  testWidgets('「文件」格走输入条既有的 @ 提及插入', (tester) async {
    await openPanel(tester);

    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '@');
    expect(tester.takeException(), isNull);
  });

  testWidgets('「+」面板有「模型」「模式」行：没有会话也能点（问题1）', (tester) async {
    var modelTaps = 0;
    var presetTaps = 0;
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
            onCommand: (line) {},
            // 还没有会话（sessionId 为 null）。
            sessionId: null,
            modelLabel: 'model-a',
            presetLabel: '标准模式',
            onPickModel: () => modelTaps++,
            onPickPreset: () => presetTaps++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('模型'), findsOneWidget);
    expect(find.text('模式'), findsOneWidget);
    // 两行都显示当前值（模型名在输入条 chip 上也有一份）。
    expect(find.text('model-a'), findsWidgets);
    expect(find.text('标准模式'), findsOneWidget);
    // 新增的两行不是开关：面板里仍然只有一个 Switch（计划模式）。
    expect(find.byType(Switch), findsOneWidget);

    // 没有会话时也能点（先选 → 建会话 → 补应用）。
    await tester.tap(find.text('模型'));
    await tester.pumpAndSettle();
    expect(modelTaps, 1);

    await tester.tap(find.text('模式'));
    await tester.pumpAndSettle();
    expect(presetTaps, 1);
  });
}
