// DshSession.agentPreset 单测（从 models_test.dart 迁出：存量文件已超 500 行
// 红线，不再往里加）。openapi §ChatSession.agentPreset 可选：桥端当前
// Agent 预设 id，空白会话可 PUT 切换、首条消息后锁定。
import 'package:dshchat/bridge/models.dart'; // re-export history_page.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DshSession.agentPreset round-trip（带/不带字段）', () {
    final withPreset = DshSession.fromJson({
      'id': 'a3', 'rootId': 'r1', 'cwd': '/x',
      'updatedAt': 0, 'running': false, 'blank': true,
      'agentPreset': 'preset-system-default',
    });
    expect(withPreset.agentPreset, 'preset-system-default');
    // 不带 agentPreset 的会话（旧桥端）→ null
    final without = DshSession.fromJson({
      'id': 'a4', 'rootId': 'r1', 'cwd': '/x',
      'updatedAt': 0, 'running': false, 'blank': false,
    });
    expect(without.agentPreset, isNull);
    // 显式 null 也走兜底
    expect(
      DshSession.fromJson({
        'id': 'a5', 'rootId': 'r1', 'cwd': '/x',
        'updatedAt': 0, 'running': false, 'blank': false,
        'agentPreset': null,
      }).agentPreset,
      isNull,
    );
  });
}
