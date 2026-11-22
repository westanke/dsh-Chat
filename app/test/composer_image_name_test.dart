/// 输入条待发送图片 chip 回归（真机反馈 2026-11-17）：
/// 图片文件名过长时，旧实现里 Chip 被放在 `Spacer` 之后的无界横排里，
/// label 没有宽度上限也不会省略 —— Chip 一路撑宽把右侧加图钮与发送钮挤出
/// Row（表现为「长文件名盖住发送键、发不出去」）。
///
/// 修法（composer_bar.dart）：有图时把 `Spacer` 换成 `Expanded`（吃剩余空间、
/// 右对齐），再叠 `ConstrainedBox(maxWidth: DsSpacing.composerImageChipMaxWidth)`
/// 封顶 + label `maxLines: 1` / `TextOverflow.ellipsis`。
/// 本用例走真实选图链路（mock dsh/platform 通道 + 真实临时文件）验证：
/// ①无 RenderFlex 溢出异常；②chip 宽度不超过 token 上限；③发送钮仍在屏内可点。
library;

import 'dart:io';

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/composer.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 100 字符的 ASCII 文件名（模拟相机/微信转存的长名；纯 ASCII 最容易撑宽）。
const _longName =
    'this_is_a_very_long_picked_image_file_name_from_the_camera_roll_'
    'that_used_to_cover_the_send_button_20261117.png';

/// 逻辑屏宽（360dp × 3.0 = 1080px，与 md_view_test 同口径）。
const _screenWidth = 360.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late File imageFile;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 临时文件放 build/ 下（已 gitignore；宪法禁 /tmp）。
    tmpDir = Directory('build/composer-image-name-test')
      ..createSync(recursive: true);
    // 真实 PNG 头 + 少量填充，够 pickComposerImage 读字节做 base64。
    imageFile = File('${tmpDir.path}/$_longName');
    imageFile.writeAsBytesSync(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG 魔数
      ...List<int>.filled(64, 0),
    ]);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/platform'), null);
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Future<void> pumpComposer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dsh/platform'),
      (method) => method.method == 'pickImage'
          ? Future<Map<String, Object>>.value(<String, Object>{
              'path': imageFile.path,
              'name': _longName,
              'mediaType': 'image/png',
            })
          : null,
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
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 点加图钮走完整链路（读文件是真实 IO，必须 runAsync 才能完成）。
  Future<void> pickLongNamedImage(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.add));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    // 2026-11-22 起「+」先弹附件面板，点「相册」才走原来的选图通路。
    await tester.runAsync(() async {
      await tester.tap(find.text('相册'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  group('输入条长文件名不挤掉发送键（2026-11-17 真机反馈）', () {
    testWidgets('长文件名 chip 封顶 + 发送键仍在屏内可点', (tester) async {
      await pumpComposer(tester);
      await pickLongNamedImage(tester);

      // 图片已挂上（chip 的 label 仍是完整文件名，只在渲染时省略号截断）。
      expect(find.text(_longName), findsOneWidget);

      // ① 没有任何布局溢出（旧实现这里会抛 RenderFlex overflow）。
      expect(tester.takeException(), isNull);

      // ② chip 宽度受 token 封顶，不会无限吃掉整行。
      final labelSize = tester.getSize(find.text(_longName));
      expect(
        labelSize.width,
        lessThanOrEqualTo(DsSpacing.composerImageChipMaxWidth),
      );

      // ③ 发送键（有图 + 空文本 → send 态实心箭头）仍在屏内、可点。
      final sendIcon = find.byIcon(Icons.arrow_upward);
      expect(sendIcon, findsOneWidget);
      final sendRect = tester.getRect(sendIcon);
      expect(sendRect.right, lessThanOrEqualTo(_screenWidth));
      expect(sendRect.left, greaterThanOrEqualTo(0.0));

      await tester.tap(sendIcon);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('点 chip 的删除标记可清掉待发送图片', (tester) async {
      await pumpComposer(tester);
      await pickLongNamedImage(tester);
      expect(find.text(_longName), findsOneWidget);

      // Chip 的删除按钮：本仓 material_ui 主题下是 [avatar icon, delete icon]
      // 两个 Icon，删除标记取 Chip 内最后一个（Icons.cancel）。
      final del = find.descendant(
        of: find.byType(Chip),
        matching: find.byType(Icon),
      );
      expect(del, findsNWidgets(2));
      await tester.tap(del.last);
      await tester.pumpAndSettle();

      expect(find.text(_longName), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
