// 冒烟测试：应用可启动并渲染连接页。
import 'package:dshchat/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots to connect page', (tester) async {
    await tester.pumpWidget(const DshChatApp());
    expect(find.text('连接到 DSH Bridge'), findsOneWidget);
  });
}
