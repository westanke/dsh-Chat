import 'package:flutter_test/flutter_test.dart';
import 'package:dshchat/bridge/device.dart';

void main() {
  test('displayName 用当前设备名称替换 Flutter', () {
    expect(DshDevice.labelFor('vivo V2080A'), 'DSH Chat (vivo V2080A)');
    expect(DshDevice.labelFor('  ICL-AL10  '), 'DSH Chat (ICL-AL10)');
    expect(DshDevice.labelFor(''), 'DSH Chat');
    expect(DshDevice.labelFor('   '), 'DSH Chat');
  });
}
