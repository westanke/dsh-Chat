/// 通知偏好与投递判据单测（对齐 dsh-go 的 NotifyPrefs.shouldPost 口径）。
library;

import 'package:dshchat/bridge/notify.dart';
import 'package:dshchat/ui/notify_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('四类开关独立生效，总开关一关全关', () async {
    final p = NotifyPrefs.instance;
    p.enabled = true;
    p.done = false;
    p.failed = true;
    expect(p.allows(NotifyKind.done), isFalse);
    expect(p.allows(NotifyKind.failed), isTrue);
    p.enabled = false;
    expect(p.allows(NotifyKind.failed), isFalse);
    p.enabled = true;
    p.done = true;
  });

  test('正在看的会话不打扰；后台一定发', () {
    // 前台 + 同会话 → 跳过
    expect(
      NotifyPrefs.shouldPost(
        allowsKind: true,
        canPost: true,
        foreground: true,
        sameSession: true,
      ),
      isFalse,
    );
    // 前台 + 别的会话 → 发（用户正停在别处，需要提示）
    expect(
      NotifyPrefs.shouldPost(
        allowsKind: true,
        canPost: true,
        foreground: true,
        sameSession: false,
      ),
      isTrue,
    );
    // 后台 → 发
    expect(
      NotifyPrefs.shouldPost(
        allowsKind: true,
        canPost: true,
        foreground: false,
        sameSession: true,
      ),
      isTrue,
    );
    // 偏好关了 / 系统不让发 → 一律不发
    expect(
      NotifyPrefs.shouldPost(
        allowsKind: false,
        canPost: true,
        foreground: false,
        sameSession: false,
      ),
      isFalse,
    );
    expect(
      NotifyPrefs.shouldPost(
        allowsKind: true,
        canPost: false,
        foreground: false,
        sameSession: false,
      ),
      isFalse,
    );
  });

  test('状态解析：缺字段按不支持处理', () {
    expect(NotifyStatus.fromMap(null).native, isFalse);
    final s = NotifyStatus.fromMap({'permission': true, 'enabled': false});
    expect(s.native, isTrue);
    expect(s.canPost, isFalse);
    expect(
      NotifyStatus.fromMap({'permission': true, 'enabled': true}).canPost,
      isTrue,
    );
  });

  test('通知载荷：可选字段为空不写进 map', () {
    const p = NotifyPayload(
      title: '回答已完成',
      text: '修一下构建',
      key: 'turn:s1',
      attention: false,
      sessionId: 's1',
    );
    final m = p.toMap();
    expect(m['key'], 'turn:s1');
    expect(m.containsKey('sessionId'), isTrue);
    expect(m.containsKey('kind'), isFalse);
    expect(m.containsKey('eventId'), isFalse);
  });
}
