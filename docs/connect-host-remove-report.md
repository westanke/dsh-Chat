# 连接页「历史主机」无删除功能 调查报告

> 反馈来源：用户 2026-11-10「连接界面的 有过期的 需要删除。没有删除功能」。
> 目标仓：`/media/wangke/OFFICE/workspace/dsh-Chat`（AGENTS.md 工程宪法适用）。

## 1. 现象与结论摘要

连接页「历史主机」列表会长期累积已失效的记录（bridge 换地址、token 被吊销、临时配对遗留），
点击只尝试直连，失败仅给一行「直连失败…（可重新配对）」文字，**没有任何删除入口**，
过期记录永远留在列表里。用户需要能删掉这些过期/失效条目。

根因不是某一处 bug，而是功能缺口：记录库 `DshHosts` 只有 `load/upsert/clear`，
没有单条删除；UI 的 `_HostCard` 只有整卡点击直连，没有删除控件。

## 2. 调查对象与约束

- 无华为/真机连接（仅有 vivo 一台且未装本 App）→ 删功能的行为只能靠代码与单元/组件测试验证，
  **未装机验证**（宪法 §9：不得写「已完成」，须标注验证边界）。
- 原仓在本轮开始前已恢复可写（`/dev/sda` rw），原生工具链
  `tools/flutter`（Flutter 3.47.9 / Dart 3.13.7）+ `tools/dsh-home` 可直接用。
- 本任务改动与上一任务（华为 HEIC）的 9 项未提交改动并存，**均不 commit、不 push**
  （宪法 §10：push/发布须用户明确同意；用户尚未回答上一任务的 commit 询问）。

## 3. 相关链路（修复前）

- `app/lib/bridge/hosts.dart`：`DshHosts` 用 shared_preferences 单键 `dsh.hosts` 存 JSON 数组；
  `upsert` 按 `baseUrl` 幂等；`clear()` 是唯一删除途径（一次性清空全部）。
  `DshHost.id = stableId(baseUrl)`（FNV-1a hex16），早期/导入数据可能 id 为空串。
- `app/lib/ui/connect_page.dart`：`build` 里 `savedHosts = _hosts.where((h) => (h.token??'').isNotEmpty)`，
  每条渲染成 `_HostCard`（整卡 `InkWell(onTap: ..._connectHost(h))`）；`_connectHost` 失败
  `setState(_error='直连失败：$e（可重新配对）')`，不记录是哪台失败。
- `app/lib/bridge/credentials.dart`：`DshCredentials.baseUrl/token`（静态）+ `load/save/clear`，
  支撑「一次配对，此后自动连接」；`app/lib/main.dart` 启动 `_autoConnect()` 拿这对凭证静默直连。

## 4. 逐条根因与修法

### 4.1 记录库缺单条删除（核心缺口）
`DshHosts` 无法按条目删除。新增
`static Future<bool> remove(DshHost host)`：
按 `baseUrl` 优先、非空 `id` 兜底匹配（`host.id.isNotEmpty` 守卫，避免空 id 脏数据误删
所有空 id 记录）；命中则更新 `_cache` 并 `sp.setString(_key, jsonEncode(...))` 写回，
删空写 `[]`（不是 `remove` 键，保证 `load()` 永远读到合法数组）；返回是否命中。

### 4.2 卡片无删除入口，且整卡点击会误连
给 `_HostCard` 右侧加独立 `IconButton(Icons.delete_outline)`：它位于卡片 `Row` 的独立
命中区，`InkWell` 只包左侧 `Expanded` 区域，两者不重叠——点删除不会触发点击直连。
删除走 `AlertDialog` 二次确认（避免误触），删后刷新 `_hosts` 列表。

### 4.3 直连失败时不知道删哪条 / 不方便删
`_connectHost` 失败时记 `_failedHost = host`（成功/手动配对/导入路径都清空它）；
错误区在 `_failedHost != null` 时补一个 `TextButton.icon`「删除这条失效记录」，
点它直接对失败的那台走二次确认删除，用户不必回到列表里找。

### 4.4 删掉当前凭证主机后，下次启动仍会静默直连失败
`_confirmRemove` 里若 `DshCredentials.baseUrl == host.baseUrl`，
顺手 `DshCredentials.clear()`，避免下次启动拿过期 token 静默直连失败。

### 4.5 样式与文档契约
新 UI 元素（删除图标、失效记录按钮）全部复用既有 `DsColors` / `DsTypography` 语义别名，
零裸色/裸字号（宪法 §4）；先登记 `docs/design-tokens.md` §4.8，再改代码。
改 lib/ 同提交改 `docs/STRUCTURE.md`（hosts.dart / connect_page.dart / hosts_test.dart 三行口径）。
单文件 `connect_page.dart` 482 行 ≤500（宪法 §7）。

## 5. 验证边界

| 项 | 结果 |
|---|---|
| `bash scripts/ci/docs-check.sh` | ✅ 通过（全部登记 / 无死链 / 无旧仓名残留） |
| `flutter pub get` | ✅（注：先清掉指向已删除副本 SDK 的旧 `.dart_tool/package_config.json`，重建后 analyze 才正常） |
| `flutter analyze` | ✅ `No issues found!` |
| `flutter test` | ✅ 129 项全过（基线 125 + 新增 `DshHosts.remove` 存储层 4 项） |
| `flutter test test/hosts_test.dart` | ✅ 10 项全过（原 6 + 新增 4） |
| Kotlin 编译 / 真机交互 | ⚠️ 未验证（本任务纯 Dart，无 Kotlin 改动；无真机） |

新增单测覆盖：删存在→true/落盘同步、删不存在→false/列表不变、按非空 id 兜底匹配、
删空写 `[]`。每个 test 先 `await DshHosts.clear()` 重置静态 `_cache`，
并 `SharedPreferences.setMockInitialValues({})` 隔离。

## 6. 落地状态与回归指引

改动文件（均写入原仓，**未提交未推送**）：
- `app/lib/bridge/hosts.dart`（新增 `remove`）
- `app/lib/ui/connect_page.dart`（卡片删除按钮 + 二次确认 + 失败入口 + 凭证清理）
- `app/test/hosts_test.dart`（4 项存储层单测）
- `docs/STRUCTURE.md`、`docs/design-tokens.md`（文档契约 + §4.8 登记）
- 本报告 `docs/connect-host-remove-report.md`

装机后建议回归：
1. 历史主机多于 1 条时，点某条右侧删除 → 弹二次确认 → 确认后只剩其余条目；取消不变。
2. 点删除按钮不会触发「点击直连」（不出现直连失败提示）。
3. 点一台已失效主机直连失败后，错误区出现「删除这条失效记录」，点它删掉的正是失败那台。
4. 删掉当前正在用的主机后，杀进程重启不再静默直连失败（应停在连接页）。
5. 删空最后一条后重启，列表为空且不报错（读到 `[]`）。
