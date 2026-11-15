import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

/**
 * 版本契约冒烟（阶段 0 首条用例）：
 * AppScope/app.json5（鸿蒙产物版本）与 entry/oh-package.json5（模块版本）必须一致。
 * 以后每一版 bump 两处都要同步 —— 三端总表里「发版改版本号」是手工活，
 * 忘了改的代价是 AGC 拒收同 versionCode 重复包（姊妹仓 1.0.2 教训）。
 * 阶段 1 起 core/ 协议层用例会陆续加入这个目录。
 */
test('AppScope 与 entry 模块版本一致', () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const app = readFileSync(join(here, '../../AppScope/app.json5'), 'utf8');
  const entry = readFileSync(join(here, '../../entry/oh-package.json5'), 'utf8');

  const verName = app.match(/"versionName"\s*:\s*"([^"]+)"/)?.[1];
  const verCode = app.match(/"versionCode"\s*:\s*(\d+)/)?.[1];
  const modVer = entry.match(/"version"\s*:\s*"([^"]+)"/)?.[1];

  assert.ok(verName, 'AppScope/app.json5 缺 versionName');
  assert.ok(verCode, 'AppScope/app.json5 缺 versionCode');
  assert.equal(modVer, verName, `entry/oh-package.json5 的 version(${modVer}) 应与 versionName(${verName}) 同步`);
  assert.equal(verName, '1.0.0', '阶段 0 基线版本应为 1.0.0（升级时同步改本断言）');
});
