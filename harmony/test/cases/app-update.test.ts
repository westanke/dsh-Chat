/**
 * AppUpdate 测试 —— 鸿蒙版「检查更新」走华为应用市场（AppGallery Kit）后的
 * 纯逻辑部分：错误码文案、结果对象、不支持文案。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  NOT_SUPPORTED_MESSAGE, UPDATE_AVAILABLE_YES, UpdateCheckResult, updateErrorMessage,
} from '../../entry/src/main/ets/core/AppUpdate.ts';

test('UpdateCheckResult.ofNew：有新版文案与 hasNew', () => {
  const r: UpdateCheckResult = UpdateCheckResult.ofNew();
  assert.equal(r.hasNew, true);
  assert.equal(r.errorCode, '');
  assert.ok(r.message.includes('应用市场'), '文案要指路应用市场');
});

test('UpdateCheckResult.ofLatest：最新版不报 hasNew', () => {
  const r: UpdateCheckResult = UpdateCheckResult.ofLatest();
  assert.equal(r.hasNew, false);
  assert.equal(r.message, '已是最新版本');
});

test('UpdateCheckResult.ofError：带回错误码且不是新版', () => {
  const r: UpdateCheckResult = UpdateCheckResult.ofError('1009400003', '');
  assert.equal(r.hasNew, false);
  assert.equal(r.errorCode, '1009400003');
  assert.ok(r.message.includes('网络'));
});

test('updateErrorMessage：SDK 全部错误码都有中文提示', () => {
  assert.ok(updateErrorMessage('1009400001', '').includes('服务连接失败'));
  assert.ok(updateErrorMessage('1009400002', '').includes('请求异常'));
  assert.ok(updateErrorMessage('1009400003', '').includes('网络'));
  assert.ok(updateErrorMessage('1009400004', '').includes('前台'));
  assert.ok(updateErrorMessage('1009400005', '').includes('隐私协议'));
  assert.ok(updateErrorMessage('1009400006', '').includes('频繁'));
  assert.ok(updateErrorMessage('1009400007', '').includes('其它'));
  assert.ok(updateErrorMessage('401', '').includes('参数'));
});

test('updateErrorMessage：未知码退回通用文案，detail 有值才拼接', () => {
  assert.equal(updateErrorMessage('9999', ''), '检查更新失败');
  assert.equal(updateErrorMessage('9999', 'boom'), '检查更新失败：boom');
});

test('NOT_SUPPORTED_MESSAGE 与 UPDATE_AVAILABLE_YES 常量口径', () => {
  assert.ok(NOT_SUPPORTED_MESSAGE.includes('不支持'));
  // SDK：UpdateAvailableCode.LATER_VERSION_EXIST = 1
  assert.equal(UPDATE_AVAILABLE_YES, 1);
});
