/// 诊断日志的两个纯判据：窗口内重复抑制 + 超限只留尾部。
///
/// 对应 companion PITFALLS「诊断日志噪音」：每帧同步写、无去重/轮转/上限，
/// 真机上把真正的现场挤出视野，`run-as cat` 整份还会卡住。
library;

import 'package:dshchat/bridge/dlog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 11, 20, 9, 0, 0);

  test('同一条消息在窗口内重复 → 抑制；换了内容或过了窗口 → 照写', () {
    expect(DshLog.shouldSuppress('a', 'a', t0, t0.add(const Duration(seconds: 1))),
        isTrue);
    expect(DshLog.shouldSuppress('b', 'a', t0, t0.add(const Duration(seconds: 1))),
        isFalse, reason: '内容不同必须写（哪怕只差一个字符）');
    expect(DshLog.shouldSuppress('a', 'a', t0, t0.add(const Duration(seconds: 3))),
        isFalse, reason: '过了窗口要写，否则「一直在重复」这件事没人知道');
    expect(DshLog.shouldSuppress('a', null, null, t0), isFalse,
        reason: '第一次出现必须写');
    // 边界：正好等于窗口不算重复（`<` 而不是 `<=`，避免抖动时全被吞）
    expect(DshLog.shouldSuppress('a', 'a', t0, t0.add(DshLog.dedupeWindow)),
        isFalse);
  });

  test('超限裁剪对齐到行首、保留的不超过上限', () {
    final content = List.generate(500, (i) => 'line $i ${'x' * 20}').join('\n');
    expect(DshLog.trimOffset(content, content.length), 0, reason: '没超不动');
    final offset = DshLog.trimOffset(content, 1000);
    expect(offset, greaterThan(0));
    expect(content.substring(offset).length, lessThanOrEqualTo(1000));
    expect(content[offset - 1], '\n', reason: '必须从整行开头保留，别留半行');
    expect(DshLog.trimOffset('abc', 0), 0, reason: 'limit<=0 视为不裁剪');
  });
}
