# 双会话并行时深度思考串台（2026-11-15）调查报告

反馈：「同时有两个会话在执行的时候，深度思考 未按照对应会话显示」。

## 复现路径与机制

1. 会话 A 在执行：`ChatState.streaming = true`，`streamReasoning` 累积 A 的
   深度思考（流式缓冲是 ChatState 上的**全局单一缓冲**，不分会话）。
2. 用户切到会话 B：`openSession(B)`（chat_state.dart）清了 rawEvents/projections/
   翻页状态，**但没清流式缓冲**（对比 `newChat()` 一直有 `_clearStream()`）。
3. B 页渲染：`_StreamingItem`（chat_message_items.dart:204）读全局
   `state.streamReasoning`/`streamText` + `state.streaming` → **B 页尾部挂着
   A 的深度思考气泡**；若 B 也在执行，B 的新 delta（`_isCurrent` 放行）
   追加在 A 残留后面，两段内容混在一起——「未按照对应会话显示」。
4. 切回 A：缓冲仍是「切走前的旧 A 内容」，与 reloadHistory 拉回的落库内容
   **重叠**（同一段思考显示两份），直到 committed 清空。

## 修复

`app/lib/ui/chat_state.dart` `openSession()`：切会话时
`streaming = false; _clearStream(); notifyListeners();` —— 与 newChat() 对齐；
notify 提前到 reloadHistory 之前，history 网络往返期间 B 页先渲染清空态，
不显示旧会话残留。切回 A 时缓冲从零累积，与落库历史衔接、不重复。

回补单测：`app/test/chat_actions_test.dart`（真实 `GatewayClient` 指向
`http://127.0.0.1:1` 不连接 + 手工灌残留状态 → openSession → 断言清空）。

## 「同时两个会话执行」的两种读法

- **切会话看另一会话 → 残留串台**：本报告修复项。
- **停在 A 只看 A 的流**：设计内行为。`_isCurrent()`（chat_state.dart:531）
  按 sessionId 过滤全部推送（delta/committed/turn-failed/session-event），
  未选会话时空态兜底也过滤（bridge「连接即重放」其它会话活跃事件不串台）；
  B 的流式进度切过去时由 reloadHistory + 后续 delta 续上。官方 App 同为
  「当前会话只显示当前会话的流」。

## 验证

`flutter analyze` 0 issue；`flutter test` 134 全绿（新增 1）。

## 遗留

- **断线重连**（`_onGatewayState(ready)`）不清流式缓冲：A 执行中断网重连后
  reloadHistory 拉落库内容，旧缓冲未清可能短暂重复。同类残留、用户未报、
  且 bridge 重连会重放当前订阅会话的活跃 delta（缓冲会续上）——单独评估，
  不混入本次提交。
- 实时帧 `chat.message.delta` 带 sessionId（MessageDelta.from 已解析），
  路由本身没有协议缺口，无需 bridge 改动。

---

# 新建会话可选工作目录（2026-11-15）调查报告

反馈：「新建会话中 默认工作目录是手机会话，能加一个可调整或者选择 会话目录吗。
历史会话不需要也变不了。」

## 现状与协议

- 手机端发送首条消息时 `send()` → `ensureMobileWorkspace()` 预建会话到
  「手机会话」工作区（`/storage/emulated/0/Android/data/.../files/workspace`），
  目录无处可改。
- bridge WS `session-create` 帧本就支持 `rootId + cwd`（cwd 为授权根内
  WirePath 相对路径，空串 = 根本身）与 `workspaceId` 两套入参（ws-sessions.ts:48），
  手机端只用了后者——**协议无缺口，纯客户端工作**。
- `file-list` 帧（ws-files.ts:41，files.read scope）即目录浏览：应答
  entries[name/path/kind/size/modifiedAt/writable] + nextCursor。
- WS 无 roots 枚举帧；多授权根场景的候选只能取自历史会话快照的
  (rootId, cwd) 去重（与官方 Web 的 New session 目录选择同口径）。

## 实现

- **模型**（models.dart）：`DshSession.cwd`；`SessionLocation{rootId?,cwd,label}`、
  `DshFileEntry`、`DshDirectoryPage`。
- **网关**（gateway_api.dart）：`createSessionAt({rootId, cwd})`（session-create
  帧，失败显式报错，不静默回退默认目录——建错地方的会话比报错更糟）；
  `listDirectory()`（file-list 帧，limit 200）。
- **状态分流**（chat_state.dart）：`pendingLocation` 待定目录；`send()` 在
  sessionId==null 时分流——已选目录走 `createSessionAt`（成功即 `pendingLocation=null`，
  会话目录定死），未选保持原手机工作区通道；`newChat()` 清待定（不沿用上次
  选择）。历史会话方法体抽 `chat_history_actions.dart`（chat_state.dart 压回
  500 行，宪法 §7）。
- **选择 sheet**（session_location_sheet.dart 新）：默认项「手机会话（默认）」+
  已选高亮（可点恢复默认）+「最近使用」（历史会话 (rootId,cwd) 去重，
  cwdAbsolute 副标题）+「浏览授权根目录…」（面包屑 + 只列目录 + 加载更多 +
  「在此目录新建会话」）。`DirectoryLister` 注入点供测试。
- **入口**（chat_page.dart）：空态问候区加工作目录 chip（手机图标/文件夹图标
  随状态切换，label = 已选 label 或「手机会话（默认）」）。

## 设计取舍

- **不在会话建立后改目录**：目录在 session-create 时定死（bridge 语义即如此，
  cwd 是会话构造参数）；用户反馈也只要新建时可选。
- **WS 无 roots 帧不扩协议**：候选取历史快照 + 浏览从「浏览授权根目录」进入时
  以第一个授权根起步；单根（主流手机场景）完全够用。后续如要多根平铺，
  加 roots 枚举帧是 bridge 独立改动。
- **sendText 失败的会话不回滚**：会话已建、目录已定，重试继续用该会话
  （sessionId 已挂上），避免反复建空白会话。

## 测试

`app/test/session_location_test.dart`（新 8 项）：模型解析 2、send 分流 3
（选了目录走 session-create{rootId,cwd} 并清待定；未选不走；newChat 清）、
sheet 交互 3（默认项 + 去重 + 绝对路径副标题 + 选中写回；已选高亮；
浏览进子目录回传相对路径）。

**教训**：Dart extension 方法静态分派——测试假网关 extends GatewayClient
覆写 extension 成员（createSessionAt）无效，必须覆写类本体方法（request()）
按 type 发假应答，顺带覆盖「extension → request」完整链路。

## 验证

`flutter analyze` 0 issue；`flutter test` 142 全绿（+8）；
`docs-check.sh` 通过。

# Flutter 3.50 拆包迁移：material.dart → material_ui（2026-11-15）

## 背景与触发

CI 升到 Flutter 3.50.0 stable 后（run #10）报 33 处 `deprecated_member_use`：
`package:flutter/material.dart` 已 deprecated，官方指引迁往独立包
`package:material_ui/material_ui.dart`（after v3.47.0-0.0.pre）。3.50 里
Material/Cupertino 组件库、全局 Material/Cupertino 本地化 delegate 全部拆出
SDK，改为 pub 包 `material_ui` / `cupertino_ui` 发布；`flutter/widgets` 与
`GlobalWidgetsLocalizations` 仍留在原处。

## 迁移内容

1. **机械替换**：`dart fix --apply` 34 处（32 文件 import 改写 + pubspec
   自动补依赖）。注意 dart fix 加的依赖是 `any`，锁不住版本，手工改为
   `material_ui: ^1.11.0`、`cupertino_ui: ^1.1.6`（迁移时 pub 镜像最新）。
2. **main.dart 手工收尾**：`GlobalMaterialLocalizations` /
   `GlobalCupertinoLocalizations` 在 `flutter_localizations` 与新包里重名
   （ambiguous_import），处理为
   `import 'package:flutter_localizations/flutter_localizations.dart'
   hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations`——保留
   `GlobalWidgetsLocalizations`，Material/Cupertino delegate 用新包版本。
3. **测试适配（render_md_test.dart）**：3.50 测试框架新增「树卸载后不得有
   残留 transient callback」的 postTest 检查。teardown 期间框架派发
   fontsChange（flutter/system channel）→ `_SystemFontsNotifier` → 残留
   render object 注册帧回调 → 判「An animation is still running even after
   the widget tree was disposed」。试过 ①末尾手动 pumpWidget 卸载树、②
   `setMockMessageHandler` 吞消息，都无效——**mock 会在 postTest 被清掉，
   fontsChange 在清理之后才派发**。最终修法：test 开头真实替换该 channel
   的 handler 吞掉系统消息（`BasicMessageChannel('flutter/system',
   JSONMessageCodec()).setMessageHandler((_) async {})`）。本文件仅一个
   测试且 flutter test 每文件独立进程，无跨测试污染。

## 验证

- `flutter analyze`（3.50.0）：0 issue。
- `flutter test`：142 全绿。
- 本机默认 SDK 已切换：`tools/flutter -> flutter-3.50.0`（软链，env.sh 的
  FLUTTER_ROOT 无需改）；旧 3.47.9 已不在。
- CI pin：ci.yml `flutter-version: 3.50.0`。
- release APK 以 3.50.0 重新构建。

## 备注

- Flutter 镜像下载路径必须含 `stable/linux/` 前缀，漏了会 404 存下错误页。
- `docs/ecosystem/material_ui`（SDK 内）是 monorepo 内部 M3E 迁移清单，
  与应用层无关；应用层迁移就是 import + delegate 两件事。

# 发版流水线：版本号、ABI 精简、iOS 在线打包（2026-11-15）

## 1. 发版必须升级版本号

版本单一来源 `app/pubspec.yaml` 的 `version: <versionName>+<versionCode>`
（Android versionCode/versionName 与 iOS CFBundleVersion 都由 Flutter 自动
注入，iOS Info.plist 用 `$(FLUTTER_BUILD_NAME)/$(FLUTTER_BUILD_NUMBER)` 引用，
无需手改）。本次 `1.0.13+14 → 1.0.14+15`。

release.yml 加了**版本核对步骤**：打 tag（约定 `v<versionName>`，如 v1.0.14）
时校验 tag 与 pubspec 版本一致，不一致直接红——防止「忘升版本就发版」。

## 2. 只留手机端/平板端：ABI 精简

universal APK 74.8MB 的构成：libapp.so ×3 ABI（~41MB）+ libflutter.so ×3
（~36MB）。手机与平板 2026 年已全面 ARM64，砍 armeabi-v7a（32 位）与
x86_64（模拟器）→ **25.9MB（-65%）**。

实现有一个坑：Flutter 3.50 的 FlutterPlugin 在无 splits 时会
`abiFilters.clear(); abiFilters.addAll(全量 3 ABI)`（FlutterPlugin.kt:444，
「Google Play 兼容设备列表」的默认行为），build.gradle.kts 里写的
`ndk { abiFilters }` 会被覆盖。官方开关是 Gradle 属性
**`disable-abi-filtering=true`**（FlutterPluginUtils.kt:318）：
app/android/gradle.properties 设上后，项目自己的
`abiFilters += listOf("arm64-v8a")` 才是唯一来源。

## 3. iOS 在线打包（本机无苹果环境）

新工作流 `.github/workflows/release.yml`（tag `v*` 或手动触发）：

- **android job**（ubuntu）：flutter 3.50.0 构建 arm64 APK → artifact
  `android-apk`。
- **ios job**（macos-15）：`flutter build ios --release --no-codesign` 出
  未签名 Runner.app → 手工打 Payload zip → 未签名 IPA → artifact `ios-ipa`。
  未签名 IPA 不能 Xcode 直接分发，用侧载工具（Sideloadly / AltStore /
  爱思助手）签名安装。

两个 job 都带版本核对；artifact 在私有仓库 Actions 页登录后下载。
macOS runner 计费约 ×10（私有仓库），一次 iOS 构建 20-30 分钟约 200-300
计费分钟，发版频率低时免费额度够用。

## 验证

- 本地 arm64 APK：25.9MB，`aapt dump badging` 显示
  versionCode='15' versionName='1.0.14'，包内无 armeabi-v7a/x86_64。
- ci.yml 头注释同步更新（发版构建指向 release.yml）。

## 续编：版本号漂移与更新链路修复（1.0.15+16）

用户在设置页截图反馈：「版本 1.0.13+14」写死没跟发版走，检查更新报
「远端 v1.0.13」（实际已发 v1.0.14）。两处独立根因：

1. **版本展示与比较基准写死**：settings_page.dart 顶层常量
   `_appVersion = '1.0.13+14'`（当时注释的理由是「不引入
   package_info_plus 避免加依赖」）。发版流水线上线后版本号会变，写死即漂移。
   修复：`dsh/platform` 通道新增 `appVersion`（Android 读 gradle
   versionName/longVersionCode、iOS 读 CFBundleShortVersionString/
   CFBundleVersion——Flutter 工具链自动从 pubspec version 注入这两个字段，
   零新依赖、零配置）；Dart 侧 `DshPlatform.appVersion()` 成功缓存、失败
   回 null 降级（About 显示占位、更新检查跳过比较，不拿 0.0.0 误报）。
2. **远端 release 附件识别不到**：release_check.dart 资产过滤只认
   `dsh-Chat-` 前缀，而 sync-gitee-release.sh 发的是 `dshchat-*`（无连
   字符），远端 v1.0.14 的 APK 被跳过 → 回退 GitHub 也没有 → 报旧版本。
   修复：小写化后 `dsh-chat-` / `dshchat-` 两前缀都放行（注意两者字面
   不同，须显式双匹配）。

配套：`fetchLatestRelease({http.Client? client})` 加注入点供测试；
测试 +6（两套命名 / Gitee→GitHub 回退 / 双站失败 / isNewerVersion 边界
/ 设置页版本行 mock 平台通道），全量 149 绿、analyze 0 issue。

发版闭环验证：修复以 v1.0.15+16 发布（tag↔pubspec 一致性核对在 CI），
GitHub 构建完成后跑 `scripts/sync-gitee-release.sh v1.0.15 <run-id>`
同步 gitee；用户手机 1.0.14 点检查更新应发现 v1.0.15 → 下载（gitee
附件直链）→ 安装后版本行与「已是最新」口径全部对齐。

## 续编二：安卓覆盖安装「签名不一致」修复（1.0.16+17）

用户反馈每次更新都提示签名不一致。根因：release.yml 未提供签名密钥，
GitHub runner 每次新机器回落**随机** debug keystore——每个 CI 包签名都
不同，覆盖安装必然被拒。

修复（提交 9548895）：
- 正式 keystore 在本机生成（RSA 2048 / 有效期 30 年 / alias dshchat），
  保存于仓库外 workspace/keys/（.gitignore 双重拉黑 key.properties 与
  *.jks，宪法 §10 绝不提交凭证）；
- build.gradle.kts 的 hasReleaseKeystore 分支是现成的（11-04 就写好了），
  本地 app/android/key.properties 指向仓库外 keystore，构建即生效
  （apksigner verify：CN=DSH Chat，SHA-256 15ffe95f…）；
- release.yml 增加签名注入步骤：KEYSTORE_BASE64/KEYSTORE_PASSWORD/
  KEY_ALIAS/KEY_PASSWORD 四个仓库 Secrets（libsodium sealed box 加密经
  REST API 上传，tweetnacl-sealedbox-js 实现），构建前解码写
  key.properties；Secrets 缺失时 warning 回落 debug（保持克隆可构建）；
- 本地与 CI 共用同一证书，此后 CI 包互相覆盖、与本地包互相覆盖都不再
  报签名不一致。

**用户迁移路径**：旧包（历史 debug 随机签名）与 1.0.16 仍不一致——
最后一次卸载重装；装上 1.0.16+17 后永久覆盖升级。
