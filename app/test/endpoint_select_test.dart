// IKX5KQ：DSH1 endpoints 变成候选列表后的探活/择优/换地址。
import 'dart:convert';
import 'dart:io';

import 'package:dshchat/bridge/endpoint_select.dart';
import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/host_connect.dart';
import 'package:dshchat/bridge/hosts.dart';
import 'package:flutter_test/flutter_test.dart';

EndpointProbe _ok(String url, int ms) =>
    EndpointProbe(baseUrl: url, ok: true, latencyMs: ms);

EndpointProbe _bad(String url) =>
    EndpointProbe(baseUrl: url, ok: false, error: '连不上');

String _dsh1(Map<String, dynamic> obj) {
  final b = base64Url.encode(utf8.encode(jsonEncode(obj))).replaceAll('=', '');
  return 'DSH1:$b';
}

void main() {
  group('地址分类', () {
    test('私有网段/回环/.local 算 LAN', () {
      for (final h in [
        '192.168.1.10',
        '10.1.2.3',
        '172.16.0.9',
        '172.31.255.1',
        '100.64.3.4',
        '127.0.0.1',
        'my-box.local',
        '[fd00::1]',
      ]) {
        expect(isPrivateHost(h), isTrue, reason: h);
      }
      expect(isPrivateHost('47.100.1.1'), isFalse);
      expect(isPrivateHost('172.32.0.1'), isFalse);
    });

    test('隧道域名归 tunnel，普通公网归 other', () {
      expect(
        classifyEndpoint('https://abc-def.trycloudflare.com'),
        EndpointKind.tunnel,
      );
      expect(classifyEndpoint('http://192.168.1.5:3090'), EndpointKind.lan);
      expect(classifyEndpoint('http://example.com:3090'), EndpointKind.other);
    });
  });

  group('择优排序', () {
    test('LAN 可达且延迟 ≤ 最快×1.5 → 选 LAN', () {
      final picked = pickEndpoint([
        _ok('https://x.trycloudflare.com', 300),
        _ok('http://192.168.1.5:3090', 40),
      ]);
      expect(picked, 'http://192.168.1.5:3090');
    });

    test('LAN 明显更慢 → 选隧道', () {
      final picked = pickEndpoint([
        _ok('https://x.trycloudflare.com', 300),
        _ok('http://192.168.1.5:3090', 900),
      ]);
      expect(picked, 'https://x.trycloudflare.com');
    });

    test('并列延迟时上次成功的地址优先', () {
      final picked = pickEndpoint(
        [
          _ok('https://x.trycloudflare.com', 100),
          _ok('http://10.0.0.2:3090', 100),
        ],
        preferred: 'https://x.trycloudflare.com',
      );
      // LAN 并列也在 LAN 门槛内，先按 LAN 优先；这里用两条隧道验证并列。
      expect(picked, 'http://10.0.0.2:3090');
      final tunnels = [
        _ok('https://a.trycloudflare.com', 120),
        _ok('https://b.trycloudflare.com', 120),
      ];
      expect(
        pickEndpoint(tunnels, preferred: 'https://b.trycloudflare.com'),
        'https://b.trycloudflare.com',
      );
    });

    test('全部不可达返回 null', () {
      expect(
        pickEndpoint([_bad('http://192.168.1.5:3090'),
          _bad('https://x.trycloudflare.com')]),
        isNull,
      );
    });

    test('normalizeEndpoints 去重保序、去尾斜杠', () {
      expect(
        normalizeEndpoints([
          'https://a/',
          ' http://b ',
          'https://a',
          '',
        ]),
        ['https://a', 'http://b'],
      );
    });
  });

  group('探活', () {
    test('healthz 200 → ok 且带延迟', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.write('{"ok":true}');
        req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final probe = await probeEndpoint(base, timeout: const Duration(seconds: 2));
      expect(probe.ok, isTrue);
      expect(probe.latencyMs, isNotNull);
      await server.close(force: true);
    });

    test('5xx → 不可达（原因非空）', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.statusCode = 500;
        req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final probe = await probeEndpoint(base, timeout: const Duration(seconds: 2));
      expect(probe.ok, isFalse);
      expect(probe.error, contains('500'));
      await server.close(force: true);
    });

    test('selectEndpoint 全失败也返回逐条原因', () async {
      final servers = <HttpServer>[];
      final urls = <String>[];
      for (var i = 0; i < 2; i++) {
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        s.listen((req) {
          req.response.statusCode = 503;
          req.response.close();
        });
        servers.add(s);
        urls.add('http://127.0.0.1:${s.port}');
      }
      final sel = await selectEndpoint(
        urls,
        timeout: const Duration(seconds: 2),
      );
      expect(sel.chosen, isNull);
      expect(sel.probes, hasLength(2));
      expect(sel.note, contains('都不通'));
      for (final s in servers) {
        await s.close(force: true);
      }
    });
  });

  group('DSH1 解码保留全部候选', () {
    test('endpoints 隧道在前 + LAN，全部留在 DshHost', () {
      final text = _dsh1({
        'displayName': '家里电脑',
        'token': 'tok-1',
        'endpoints': [
          {'baseUrl': 'https://abc.trycloudflare.com/api/v1'},
          {'baseUrl': 'http://192.168.1.5:3090/'},
          {'baseUrl': 'http://100.64.0.7:3090'},
        ],
      });
      final host = decodeDsh1(text);
      expect(host, isNotNull);
      expect(host!.baseUrl, 'https://abc.trycloudflare.com');
      expect(host.candidates, [
        'https://abc.trycloudflare.com',
        'http://192.168.1.5:3090',
        'http://100.64.0.7:3090',
      ]);
      expect(host.preferredEndpoint, 'https://abc.trycloudflare.com');
      expect(host.token, 'tok-1');
      expect(host.id, DshHost.stableId('https://abc.trycloudflare.com'));
    });

    test('老码只有一条地址：候选表就一条，行为不变', () {
      final text = _dsh1({
        'endpoints': [
          {'baseUrl': 'http://192.168.1.10:3090'},
        ],
      });
      final host = decodeDsh1(text)!;
      expect(host.candidates, ['http://192.168.1.10:3090']);
      expect(host.baseUrl, 'http://192.168.1.10:3090');
    });

    test('toJson/fromJson 往返保留 endpoints 与 preferredEndpoint', () {
      const h = DshHost(
        id: 'x',
        displayName: 'd',
        baseUrl: 'https://a.trycloudflare.com',
        lastUsedAt: 7,
        endpoints: ['https://a.trycloudflare.com', 'http://10.0.0.2:3090'],
        preferredEndpoint: 'http://10.0.0.2:3090',
      );
      final back = DshHost.fromJson(h.toJson());
      expect(back.endpoints, h.endpoints);
      expect(back.preferredEndpoint, 'http://10.0.0.2:3090');
      expect(back.candidates.first, 'https://a.trycloudflare.com');
    });
  });

  group('网关换地址', () {
    test('rotateEndpoint 按候选表循环，单地址不换', () {
      final gw = GatewayClient(baseUrl: 'http://a')
        ..setEndpointCandidates(['http://a', 'https://b', 'http://c']);
      expect(gw.baseUrl, 'http://a');
      expect(gw.rotateEndpoint(), isTrue);
      expect(gw.baseUrl, 'https://b');
      expect(gw.rotateEndpoint(), isTrue);
      expect(gw.baseUrl, 'http://c');
      expect(gw.rotateEndpoint(), isTrue);
      expect(gw.baseUrl, 'http://a');
      gw.dispose();

      final single = GatewayClient(baseUrl: 'http://only');
      expect(single.rotateEndpoint(), isFalse);
      expect(single.baseUrl, 'http://only');
      single.dispose();
    });

    test('setEndpointCandidates：当前地址不在表里就以表首为准', () {
      final gw = GatewayClient(baseUrl: 'http://old')
        ..setEndpointCandidates(['https://new1', 'https://new2']);
      expect(gw.baseUrl, 'https://new1');
      expect(gw.endpointCandidates, ['https://new1', 'https://new2']);
      gw.dispose();
    });
  });

  group('connectHost 前置校验', () {
    test('没有 token 直接报错（不走网络）', () async {
      const host = DshHost(
        id: 'x',
        displayName: 'd',
        baseUrl: 'http://127.0.0.1:1',
        lastUsedAt: 1,
      );
      await expectLater(
        connectHost(host),
        throwsA(
          isA<HostConnectException>().having(
            (e) => e.message,
            'message',
            contains('token'),
          ),
        ),
      );
    });
  });
}
