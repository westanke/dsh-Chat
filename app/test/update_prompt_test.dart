/// 更新提示判据单测（启动弹窗的「要不要打扰」逻辑）。
library;

import 'package:dshchat/bridge/release_check.dart';
import 'package:dshchat/ui/update_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

ReleaseInfo _rel(String tag) => ReleaseInfo(
  tag: tag,
  apkUrl: 'https://example.com/app.apk',
  apkName: 'app.apk',
);

void main() {
  test('versionPartsOf：三段解析，脏值补 0', () {
    expect(versionPartsOf('1.0.27+28'), [1, 0, 27]);
    expect(versionPartsOf('2'), [2, 0, 0]);
    expect(versionPartsOf('x.y.z'), [0, 0, 0]);
  });

  test('新版提示；同版本/更旧不提示', () {
    expect(
      shouldPromptUpdate(localVersion: '1.0.26+27', latest: _rel('v1.0.27')),
      isTrue,
    );
    expect(
      shouldPromptUpdate(localVersion: '1.0.27+28', latest: _rel('v1.0.27')),
      isFalse,
    );
    expect(
      shouldPromptUpdate(localVersion: '1.0.28+29', latest: _rel('v1.0.27')),
      isFalse,
    );
  });

  test('点过「稍后」的版本不再弹，换了 tag 重新弹', () {
    expect(
      shouldPromptUpdate(
        localVersion: '1.0.26+27',
        latest: _rel('v1.0.27'),
        skippedTag: 'v1.0.27',
      ),
      isFalse,
    );
    expect(
      shouldPromptUpdate(
        localVersion: '1.0.26+27',
        latest: _rel('v1.0.28'),
        skippedTag: 'v1.0.27',
      ),
      isTrue,
    );
  });

  test('版本读不到（空串）一律不打扰', () {
    expect(
      shouldPromptUpdate(localVersion: '', latest: _rel('v9.9.9')),
      isFalse,
    );
  });
}
