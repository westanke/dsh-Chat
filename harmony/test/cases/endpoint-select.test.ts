/**
 * EndpointSelect（IKX5KQ）纯逻辑测试：地址分类 / 择优 / 诊断文案 /
 * DSH1 候选表解码与主机记录。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  EndpointProbe, EndpointKind, isPrivateHost, classifyEndpoint,
  normalizeEndpoints, pickEndpoint, selectionNote, hostOf,
} from '../../entry/src/main/ets/core/EndpointSelect.ts';
import { DshHost, decodeDsh1, candidatesOf, upsertHost }
  from '../../entry/src/main/ets/core/Hosts.ts';

function ok(url: string, ms: number): EndpointProbe {
  return new EndpointProbe(url, true, ms, '');
}

function bad(url: string): EndpointProbe {
  return new EndpointProbe(url, false, -1, '连不上');
}

function dsh1(obj: Object): string {
  return 'DSH1:' + Buffer.from(JSON.stringify(obj), 'utf8').toString('base64url');
}

test('hostOf：剥协议/路径/端口，保留 IPv6 方括号', () => {
  assert.equal(hostOf('http://192.168.1.5:3090/x'), '192.168.1.5');
  assert.equal(hostOf('https://a.trycloudflare.com/api/v1'), 'a.trycloudflare.com');
  assert.equal(hostOf('http://[fd00::1]:3090'), '[fd00::1]');
});

test('私有网段/回环/.local 算 LAN，公网不算', () => {
  for (const h of ['192.168.1.10', '10.1.2.3', '172.16.0.9', '172.31.255.1',
    '100.64.3.4', '127.0.0.1', 'my-box.local', '[fd00::1]']) {
    assert.equal(isPrivateHost(h), true, h);
  }
  assert.equal(isPrivateHost('47.100.1.1'), false);
  assert.equal(isPrivateHost('172.32.0.1'), false);
});

test('classifyEndpoint：隧道域名归 TUNNEL，私有归 LAN，其余 OTHER', () => {
  assert.equal(classifyEndpoint('https://abc.trycloudflare.com'), EndpointKind.TUNNEL);
  assert.equal(classifyEndpoint('http://192.168.1.5:3090'), EndpointKind.LAN);
  assert.equal(classifyEndpoint('http://example.com:3090'), EndpointKind.OTHER);
});

test('normalizeEndpoints：去重保序、去尾斜杠与空白', () => {
  assert.deepEqual(normalizeEndpoints(['https://a/', ' http://b ', 'https://a', '']),
    ['https://a', 'http://b']);
});

test('pickEndpoint：LAN 达标优先；LAN 太慢选隧道；全失败 null', () => {
  assert.equal(pickEndpoint([ok('https://x.trycloudflare.com', 300),
    ok('http://192.168.1.5:3090', 40)], null), 'http://192.168.1.5:3090');
  assert.equal(pickEndpoint([ok('https://x.trycloudflare.com', 300),
    ok('http://192.168.1.5:3090', 900)], null), 'https://x.trycloudflare.com');
  assert.equal(pickEndpoint([bad('http://a'), bad('https://b')], null), null);
});

test('pickEndpoint：并列延迟时上次成功的地址优先', () => {
  const probes: EndpointProbe[] = [ok('https://a.trycloudflare.com', 120),
    ok('https://b.trycloudflare.com', 120)];
  assert.equal(pickEndpoint(probes, 'https://b.trycloudflare.com'),
    'https://b.trycloudflare.com');
});

test('selectionNote：成功给「选了哪条/为什么」，全失败逐条原因', () => {
  const picked: string | null = 'http://192.168.1.5:3090';
  const note: string = selectionNote([ok('https://x.trycloudflare.com', 300),
    ok('http://192.168.1.5:3090', 40)], picked);
  assert.ok(note.indexOf('试了 2 条') >= 0);
  assert.ok(note.indexOf('局域网优先') >= 0);
  const failed: string = selectionNote([bad('http://a'), bad('https://b')], null);
  assert.ok(failed.indexOf('都不通') >= 0);
});

test('decodeDsh1：endpoints 全留（隧道在前 + LAN + CGNAT）', () => {
  const text: string = dsh1({
    displayName: '家里电脑',
    token: 'tok-1',
    endpoints: [
      { baseUrl: 'https://abc.trycloudflare.com/api/v1' },
      { baseUrl: 'http://192.168.1.5:3090/' },
      { baseUrl: 'http://100.64.0.7:3090' },
    ],
  });
  const host: DshHost | null = decodeDsh1(text, 1000);
  assert.notEqual(host, null);
  const h: DshHost = host as DshHost;
  assert.equal(h.baseUrl, 'https://abc.trycloudflare.com');
  assert.deepEqual(h.endpoints, ['https://abc.trycloudflare.com',
    'http://192.168.1.5:3090', 'http://100.64.0.7:3090']);
  assert.equal(h.preferredEndpoint, 'https://abc.trycloudflare.com');
  assert.deepEqual(candidatesOf(h), h.endpoints);
});

test('decodeDsh1：老码单地址行为不变', () => {
  const host: DshHost | null = decodeDsh1(dsh1({
    endpoints: [{ baseUrl: 'http://192.168.1.10:8765' }],
  }), 5);
  assert.notEqual(host, null);
  assert.deepEqual(candidatesOf(host as DshHost), ['http://192.168.1.10:8765']);
});

test('DshHost fromJson/toJson 往返保留 endpoints 与 preferredEndpoint', () => {
  const h: DshHost = new DshHost();
  h.id = 'x';
  h.displayName = 'd';
  h.baseUrl = 'https://a.trycloudflare.com';
  h.endpoints = ['https://a.trycloudflare.com', 'http://10.0.0.2:3090'];
  h.preferredEndpoint = 'http://10.0.0.2:3090';
  h.lastUsedAt = 7;
  const back: DshHost = DshHost.fromJson(h.toMap());
  assert.deepEqual(back.endpoints, h.endpoints);
  assert.equal(back.preferredEndpoint, 'http://10.0.0.2:3090');
});

test('upsertHost：同 id 换地址更新同一行，不新增', () => {
  const a: DshHost = new DshHost();
  a.id = 'same';
  a.baseUrl = 'https://t.trycloudflare.com';
  a.lastUsedAt = 1;
  const b: DshHost = new DshHost();
  b.id = 'same';
  b.baseUrl = 'http://192.168.1.5:3090';
  b.lastUsedAt = 2;
  const out: DshHost[] = upsertHost([a], b);
  assert.equal(out.length, 1);
  assert.equal(out[0].baseUrl, 'http://192.168.1.5:3090');
});
