// 会话侧栏 TAB 去重：顶栏已有成员/待办入口，面板不再重复「团队」「任务」。
import 'package:dshchat/ui/session_tabs_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('会话侧栏不再包含团队/任务 TAB', () {
    final labels = sessionTabsOf().map((t) => t.label).toList();
    expect(labels, isNot(contains('团队')));
    expect(labels, isNot(contains('任务')));
    expect(labels, containsAll(<String>['信息', '统计', '轨迹']));
  });
}
