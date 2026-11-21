/// 屏内右滑呼出抽屉的阈值判定（问题 3）。
library;

import 'package:dshchat/ui/chat_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('位移够远就开抽屉，反向滑动永远不开', () {
    expect(drawerSwipeOpens(0, 0), isFalse);
    expect(drawerSwipeOpens(-120, -2000), isFalse);
    expect(drawerSwipeOpens(63.9, 0), isFalse);
    expect(drawerSwipeOpens(64, 0), isTrue);
  });

  test('轻扫必须越过最小行程，且速度达标', () {
    expect(drawerSwipeOpens(23, 3000), isFalse);
    expect(drawerSwipeOpens(30, 699), isFalse);
    expect(drawerSwipeOpens(30, 700), isTrue);
  });
}
