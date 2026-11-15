// release_check 单测（2026-11-15 更新链路修复）：
// - 附件匹配两套历史命名（dsh-Chat-v*.apk / dshchat-*_N-android.apk）
// - Gitee 失败回退 GitHub
// - 版本比较 isNewerVersion 边界
import 'dart:convert';

import 'package:dshchat/bridge/release_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object> _release(String tag, List<Map<String, Object>> assets) =>
    {'tag_name': tag, 'body': 'notes', 'assets': assets};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('识别 sync-gitee-release.sh 命名（dshchat- 前缀）', () async {
    final client = MockClient((r) async => _json(_release('v1.0.14', [
          {
            'name': 'dshchat-1.0.14_15-android.apk',
            'browser_download_url':
                'https://gitee.com/westanke/dsh-Chat/releases/download/v1.0.14/x.apk',
            'size': 27053056,
          },
        ])));
    final rel = await fetchLatestRelease(client: client);
    expect(rel.tag, 'v1.0.14');
    expect(rel.versionParts, [1, 0, 14]);
    expect(rel.apkName, 'dshchat-1.0.14_15-android.apk');
    expect(rel.size, 27053056);
  });

  test('仍识别 release.sh 旧命名（dsh-Chat- 前缀）', () async {
    final client = MockClient((r) async => _json(_release('v1.0.13', [
          {
            'name': 'dsh-Chat-v1.0.13.apk',
            'browser_download_url': 'https://example.com/a.apk',
          },
        ])));
    expect((await fetchLatestRelease(client: client)).apkName,
        'dsh-Chat-v1.0.13.apk');
  });

  test('非 APK / 异名资产被跳过；无 APK 抛异常', () async {
    final none = MockClient((r) async =>
        _json(_release('v1.0.14', [
          {
            'name': 'dshchat-1.0.14_15-ios-unsigned.ipa',
            'browser_download_url': 'https://example.com/a.ipa',
          },
        ])));
    expect(() => fetchLatestRelease(client: none), throwsException);
  });

  test('Gitee 挂了回退 GitHub', () async {
    final client = MockClient((r) async {
      if (r.url.host.endsWith('gitee.com')) {
        return http.Response('gateway timeout', 504);
      }
      return _json(_release('v1.0.15', [
        {
          'name': 'dshchat-1.0.15_16-android.apk',
          'browser_download_url': 'https://github.com/x.apk',
        },
      ]));
    });
    final rel = await fetchLatestRelease(client: client);
    expect(rel.tag, 'v1.0.15');
    expect(rel.versionParts, [1, 0, 15]);
  });

  test('两站都失败抛异常', () async {
    final client = MockClient((r) async => http.Response('err', 503));
    expect(() => fetchLatestRelease(client: client), throwsException);
  });

  test('isNewerVersion 逐位比较：相等/更高/更低/补零', () {
    expect(isNewerVersion([1, 0, 14], [1, 0, 14]), isFalse);
    expect(isNewerVersion([1, 0, 15], [1, 0, 14]), isTrue);
    expect(isNewerVersion([1, 0, 14], [1, 0, 15]), isFalse);
    expect(isNewerVersion([1, 1, 0], [1, 0, 99]), isTrue);
    expect(isNewerVersion([2, 0, 0], [1, 9, 9]), isTrue);
  });
}
