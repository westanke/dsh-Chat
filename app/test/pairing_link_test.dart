import 'package:dshchat/bridge/pairing_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析一行短码：地址#配对码', () {
    final link = parsePairingLink('https://a-b-c.trycloudflare.com#AB3DE7JK');
    expect(link, isNotNull);
    expect(link!.baseUrl, 'https://a-b-c.trycloudflare.com');
    expect(link.code, 'AB3DE7JK');
    expect(link.endpoints, ['https://a-b-c.trycloudflare.com']);
  });

  test('多地址短码：逗号分隔的候选表 + 末尾配对码', () {
    final link = parsePairingLink(
      'https://x.trycloudflare.com,http://192.168.1.126:3090,http://100.64.250.1:3090#AB3DE7JK',
    );
    expect(link?.endpoints, [
      'https://x.trycloudflare.com',
      'http://192.168.1.126:3090',
      'http://100.64.250.1:3090',
    ]);
    expect(link?.baseUrl, 'https://x.trycloudflare.com');
    expect(link?.code, 'AB3DE7JK');
  });

  test('带说明的回复只看第一行，并去掉尾部斜杠与 /api/v1', () {
    final link = parsePairingLink(
      '  http://192.168.1.126:3090/api/v1/, http://100.64.250.1:3090#AB3DE7JK\n（10 分钟内有效，只能用一次）',
    );
    expect(link?.endpoints, ['http://192.168.1.126:3090', 'http://100.64.250.1:3090']);
    expect(link?.code, 'AB3DE7JK');
  });

  test('不是短码就返回 null，交给 DSH1 分支', () {
    expect(parsePairingLink(''), isNull);
    expect(parsePairingLink('DSH1:eyJkaXNwbGF5TmFtZSI6'), isNull);
    expect(parsePairingLink('https://x.trycloudflare.com'), isNull);
    expect(parsePairingLink('https://x.trycloudflare.com#'), isNull);
    // 配对码含非法字符
    expect(parsePairingLink('https://x.trycloudflare.com#ab cd'), isNull);
    // 地址不是 http(s)
    expect(parsePairingLink('ftp://x#AB3DE7JK'), isNull);
  });

  test('地址里的 # 不会误切：取最后一个 # 之后当配对码', () {
    final link = parsePairingLink('http://h:3090/p#a#AB3DE7JK');
    expect(link?.baseUrl, 'http://h:3090/p#a');
    expect(link?.code, 'AB3DE7JK');
  });

  test('接受带方括号的 IPv6 地址', () {
    final link = parsePairingLink(
      'http://[2409:8a74:8884:c780::2]:3090#AB3DE7JK',
    );
    expect(link, isNotNull);
    expect(link!.endpoints, ['http://[2409:8a74:8884:c780::2]:3090']);
    expect(link.code, 'AB3DE7JK');
  });
}
