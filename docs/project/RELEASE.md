# 发版流程 — dsh-Chat（三端：Android / iOS / 鸿蒙）

> 回答：版本号怎么定、包怎么出、怎么发、发完回读什么。
> 工程宪法在 [`AGENTS.md`](../../AGENTS.md) §10（推送纪律）与 §6（命令口径）。
> 本文件是**操作手册**；踩坑细节看 `AGENTS.md` §11 的坑位索引。
>
> **铁律**（`AGENTS.md` §10）：未经用户明确同意，不 push / release / tag / 上传产物。
> 本地 commit、构建、测试、写文档可以直接做。

---

## 0. 三端现状一览

| 平台 | 产物 | 怎么出 | 能不能上架 | 当前状态 |
|---|---|---|---|---|
| Android | `.apk` | `flutter build apk --release --target-platform android-arm64` | 能（APK 直传 Gitee Release） | **已发版**（v1.0.38），已装机验证（vivo V2080A） |
| 鸿蒙 | `.hap`（本机 signed/unsigned）/ `.app`（上架） | `flutter build hap --release --no-codesign` + `scripts/sign-hap.sh` / `flutter build app` | 本机可出**本地签名 HAP**；AGC 上架仍需 AGC 账号与 `.app` | **已真机验证**（ICL-AL10 / API 26，debug 签名安装 v1.0.38） |
| iOS | `.ipa` | 本机 Linux **打不了** → GitHub Actions macOS（`release.yml` 已改用 Flutter-OH）打未签名 IPA | 需 Apple 开发者证书 | **2026-11-25 已在 `macos-15` runner 实跑成功**（未签名 IPA 12,128,741 字节，run 45613676673）；未真机；iOS 原生桥已补齐通知/TTS/分享/选图/打开文件，安装走 App Store |

三端**共用一份 Dart 代码**（`app/lib/`）。平台差异全在两处：

- `app/ohos/entry/src/main/ets/` —— 鸿蒙宿主工程 + 三个自研 MethodChannel 插件；
- `app/android/`、`app/ios/` —— 各自的平台壳。

---

## 1. 工具链（出包前必须先 source）

```sh
source /media/wangke/OFFICE/workspace/tools/env.sh
```

`env.sh` 是**唯一入口**，它设了：

| 变量 | 值 | 为什么 |
|---|---|---|
| `FLUTTER_ROOT` | `tools/flutter-oh` | **Flutter-OH `3.50.0+ohos-1.3.3`**。三端必须统一用它——上游 Flutter 的 `TargetPlatform` 没有 `ohos` 常量，编不过 ohos fork 的 material_ui（`AGENTS.md` §11 `上游 Flutter 编不过 ohos fork`） |
| `JAVA_HOME` | `tools/jdk17` | Android 构建 |
| `ANDROID_HOME` | `tools/sdk` | Android SDK；adb 在 `tools/sdk/platform-tools/adb` |
| `GRADLE_USER_HOME` | `tools/gradle-home` | gradle 缓存（走腾讯 wrapper 镜像） |
| `DEVECO_SDK_HOME` / `HOS_SDK_HOME` | `tools/ohos-sdk/sdk` | HarmonyOS SDK **API 26**（26.0.0.105）。API 18 编不过 |
| `HDC_HOME` / `DEVECO_HOME` / `DEVECO_NODE_HOME` | `tools/ohos-sdk/…` | hdc / ohpm / hvigorw / node |
| `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL` | flutter-io.cn | 国内镜像 |

> CI 的 Android / iOS job 不装完整 HarmonyOS SDK：`scripts/ci/setup-flutter-oh.sh`
> 在 `HOS_SDK_HOME` / `DEVECO_SDK_HOME` 都未设置时，会在 Flutter-OH 根目录建
> `.hos-sdk-stub/{hmscore,openharmony}` 空骨架，仅满足 Flutter-OH 写
> `ohos/local.properties` 时的 SDK 探测；真正构建 HAP 的 self-hosted job
> 必须提供完整 SDK，脚本不会覆盖已有的 `HOS_SDK_HOME` / `DEVECO_SDK_HOME`。

> ⚠️ 不 source 就构建会用系统 `/usr/lib/android-sdk`，报
> `LicenceNotAcceptedException: Failed to install the following Android SDK packages ... ndk;28.2.13676358`。

---

## 2. 本机自测（不涉及任何远端动作，可随时做）

```sh
source /media/wangke/OFFICE/workspace/tools/env.sh
cd app

flutter pub get                                  # 依赖变更后必跑
flutter analyze                                  # 提交前必绿
flutter test                                     # 621 例

# Android 调试包（装机验证用）
flutter build apk --debug
# 产物：app/build/app/outputs/flutter-apk/app-debug.apk

# 鸿蒙调试包（本机无签名，必须 --no-codesign）
flutter build hap --debug --no-codesign
# 产物：app/build/ohos/hap/entry-default-unsigned.hap
```

真机装机：

```sh
# Android
tools/sdk/platform-tools/adb install -r app/build/app/outputs/flutter-apk/app-debug.apk
# vivo 会弹风险拦截页：勾「已了解应用的风险检测结果」再点继续安装

# 鸿蒙（需要先 hdc 连接设备）
hdc list targets
hdc install app/build/ohos/hap/entry-default-unsigned.hap
```

---

## 3. 发版：四阶段

v1.0.17 以来实测定稿，照做不出错。阶段 A/B 由 `scripts/release.sh` 承担，
阶段 C/D 需要 GitHub Actions + API。

### 阶段 A · 本机构包 + 回填文档（不推送）

```sh
cd /media/wangke/OFFICE/workspace/dsh-Chat
source /media/wangke/OFFICE/workspace/tools/env.sh

# 1) 先 bump 版本：app/pubspec.yaml 的 version: <name>+<code>
#    versionName 1.0.36 / versionCode 37 → 1.0.37 / 38
#    versionCode 必须比上一个 Release 大，否则应用市场拒收

# 2) 跑发版脚本（阶段 A）
bash scripts/release.sh
```

阶段 A 做的事：

1. **门禁**：`scripts/ci/docs-check.sh` → `flutter analyze` → `flutter test`；
2. **Android 打包**：`flutter build apk --release --target-platform android-arm64`
   （只 arm64 单 ABI：三 ABI 全打约 74 MB，只打 arm64 约 26.5 MB）；
3. **鸿蒙打包**：`flutter build hap --release --no-codesign`
   （AOT 产物约 34 MB；默认 unsigned 用于本机验证。要出本地签名包用
   `HAP_SIGN=1 bash scripts/release.sh`，口令走环境变量，见下）；
4. **回填**：`scripts/backfill-release.py` 把版本号、字节数、SHA-256 写进
   `README.md` 的「当前状态」与「下载安装」两处，并写 `artifacts/SHA256SUMS.txt`；
5. 自检 README 徽章版本唯一性。

脚本的环境开关：

| 变量 | 作用 |
|---|---|
| `DRY_RUN=1` | 只打印计划，不动文件 |
| `SKIP_CHECK=1` | 跳过门禁（已在别处跑过） |
| `BUILD_HAP=0` | 不构建鸿蒙 HAP（只发 Android 时） |
| `HAP_SIGN=1` | 构建后用 `scripts/sign-hap.sh` 签 HAP；默认只出 unsigned |
| `HAP_KEYSTORE_PWD` / `HAP_KEY_PWD` | 签名口令（`HAP_SIGN=1` 时必填；`HAP_KEY_PWD` 默认同 store） |
| `HAP_KEY_ALIAS` | 默认 `dsh-chat-harmony` |
| `FLUTTER=…` | 覆盖 SDK 路径（默认 `tools/flutter-oh/bin/flutter`） |

签名 HAP（不经过完整发版脚本，单独签也可）：

```sh
# 先把 harmony/signing/README.txt 里的 store/key 口令读进环境变量（不要写进命令历史/仓库）
export HAP_KEYSTORE_PWD=...
export HAP_KEY_PWD=...
bash scripts/sign-hap.sh \
  app/build/ohos/hap/entry-default-unsigned.hap \
  artifacts/dsh-Chat-v1.0.37-harmony.hap
# 脚本内部用 verify-app 验签；默认 release 材料（发布证书 + 发布 p7b）
```

阶段 A 结束后**人工**做：

```sh
git add -A && git commit -m "release: v1.0.37+38 产物与文档"
```

> 为什么要先提交：tag 必须指向「文档与产物一致」的提交，否则 tag 里是旧文档，
> 变成「文档描述一个不存在的状态」。阶段 B 会校验 tag 内的
> `artifacts/SHA256SUMS.txt` 与本地一致，不一致直接中止。

### 阶段 B · 双站 Release（**须用户明确同意**）

```sh
bash scripts/release.sh --publish
```

依次做：

1. 前置检查：工作区必须干净、`artifacts/` 产物存在、README 里的 SHA 与产物一致；
2. 打 annotated tag（tag=v<versionName>），校验 tag 内 `SHA256SUMS.txt` 与本地 `cmp` 一致；
3. `PUSH_TAGS=1 bash scripts/push-all.sh` —— 推 Gitee 主站 + AtomGit 备站
   （分支先推、tag 再**逐个**推，不用 `git push --tags`）；
4. 建 **Gitee Release**（API v5）：`access_token` 必须挂 query 不进 JSON body
   （挂 body 会报 40001）；附件上传 APK + HAP + SHA256SUMS.txt；
5. 建 **AtomGit Release**（API v5）：**该站不支持附件**，正文写 Gitee 下载链接；
   该接口按创建时间**升序**返回，要在整个 `per_page=100` 里找本 tag，不能取首项；
6. **回读**：Gitee 的 APK / HAP 下载链接 HTTP 200、下载回来的字节 SHA 与本地一致、
   两站 tag 都在。

### 阶段 C · iOS IPA（两段式，本机打不了）

1. 触发镜像立即同步（别等 3 小时 cron）：

   ```sh
   curl -X POST https://api.github.com/repos/westanke/dsh-Chat/actions/workflows/mirror-sync.yml/dispatches \
     -d '{"ref":"main"}' -H "Authorization: Bearer <github token>"
   ```

2. 等 main 就位（约 45 秒；GitHub main HEAD == 本地 HEAD 才继续），
   tag 随 mirror 上传后 `release.yml`（`on: push tags v*`）自动跑：
   ubuntu 用 `scripts/ci/setup-flutter-oh.sh` 装 Flutter-OH 后打 APK；
   macos-15（arm64）用同一脚本打未签名 iOS IPA；
   HAP 是可选 job：仓库变量 `BUILD_HAP=true` 且接好 `[self-hosted, linux, harmonyos]` runner 才跑；
3. `bash scripts/sync-gitee-release.sh v<ver> <run-id> ios-ipa` 把 IPA 传上 Gitee Release；
4. ⚠️ 该脚本会**删 Gitee release 旧附件**再传 —— APK / SHA256SUMS 会被删，
   要用 `POST /repos/westanke/dsh-Chat/releases/<id>/attach_files -F file=@…` 重传。

### 阶段 D · GitHub Release + CI 绿检查

GitHub Release 对象**不随 mirror**，必须用 API 补建：

```sh
curl -X POST https://api.github.com/repos/westanke/dsh-Chat/releases \
  -H "Authorization: Bearer <github token>" -d '{"tag_name":"v<ver>", …}'
```

附件：APK / SHA256SUMS /（可选）HAP 从 `artifacts/` 上传，IPA 从 Gitee Release
下载后上传（`uploads.github.com`）。最后查 Actions 全绿（`ci.yml` 三道闸门 +
`release.yml` 的 Android / iOS job；HAP job 若启用也要绿）。

---

## 4. 凭据与远端口径

| 站 | 用途 | 凭据位置 |
|---|---|---|
| Gitee | **主站**，Release 产物落这里 | `~/.config/dsh-git/tokens.conf` 的 `gitee.com` 行 |
| AtomGit | **备站**，只建 Release 对象 + 正文给 Gitee 链接 | 同上的 `atomgit.com` 行 |
| GitHub | **镜像从站**，由 `mirror-sync.yml` 每 3 小时从 Gitee `push --mirror` 同步 | `~/.git-credentials` 里的 token（`tokens.conf` 的 github 行已 401 失效，勿用） |

- 本机到 `github.com:443` 长期被阻断，`api.github.com` 可达；
- `tokens.conf` 可能读不到（构建期 `HOME` 常被覆盖到 `tools/dsh-home`），
  `scripts/release.sh` 已做 `/home/wangke` 绝对路径兜底；
- 三远端走 **SSH**（`~/.ssh/id_ed25519_{gitee,atomgit,github}`），本机没有 PAT，
  不要改成 HTTPS。

---

## 5. 鸿蒙上架（本机暂时做不了，将来要做时看这里）

本机**已有** release/debug 的 p12、证书与 p7b（`harmony/signing/`，**绝不入库**，
`.gitignore` 已拉黑）；`scripts/sign-hap.sh` 已实测能签 HAP 并 `verify-app` 通过。
上架仍缺的是：**AGC 账号/AGC 项目**，以及上架用的 `.app`（`.hap` 是安装包，不是上架包）。
签名材料只保留在本机 `harmony/signing/`；旧的 `harmony/docs/RELEASE.md` 已随 ArkTS 工程一并移除（历史见 git）。

上架流程要点：

1. 上架用 **`.app` 不是 `.hap`** —— `flutter build app`（顶层子命令）；
2. 签名配置写进 `app/ohos/build-profile.json5` 的 `app.signingConfigs`
   （口令**不能**明文写在 json5 里，走环境变量或 `hap-sign-tool`）；
3. AGC 上架审核会拒收非 **1024×1024** 的应用图标；
4. 鸿蒙应用**只能 AppGallery 分发、不允许自更新** —— 应用内更新逻辑已按此口径写
   （`app/lib/bridge/platform.dart` 的 `supportsInAppUpdate` 只在 Android 为真，
   鸿蒙/iOS 会提示「请到应用市场搜索升级」）。

---

## 6. 排障速查

| 现象 | 原因与解法 |
|---|---|
| `LicenceNotAcceptedException ... ndk;28.2.13676358` | 没 source `tools/env.sh`，用到了系统 Android SDK |
| `Error: There's no constant named 'ohos' in 'TargetPlatform'` | 用了上游 Flutter SDK；必须 `tools/flutter-oh`（CI 也要跟着改） |
| `Auto-signing: AGC login required` | HAP 构建默认要签名；本机一律 `--no-codesign`，要签名用 `scripts/sign-hap.sh` |
| `Invalid kernel binary format version (expected 130, found 141)` | `gen_snapshot` 与 patched SDK 的 Dart 版本不配；`scripts/ci/setup-flutter-oh.sh` 已把 `ohos-arm64-release/linux-x64.zip` 指向 CPF 的 Dart 3.14.0 工件，干净环境重跑该脚本即可 |
| `dartaotruntime: Syntax error: Unterminated quoted string` | `bin/cache/dart-sdk-ohos/bin/dartaotruntime` 是 macOS Mach-O；要从 `bin/cache/dart-sdk/` 拷 Linux 版覆盖（同理 `frontend_server_aot.dart.snapshot`） |
| `dart:async is not available on this platform` / `Type 'Color' not found` | release 构建缺 `flutter_patched_sdk_product`；下载 URL **不带 `common/` 这一层** |
| `Member not found: 'ohosArm'` | SDK 缓存里的 Dart SDK 不是 ohos 定制版；换 SDK 前先 `rm -rf` 旧目录（`cp -a` 进已存在目录会嵌套） |
| Gitee Release 建出来 40001 | `access_token` 放进了 JSON body；必须挂 query |
| AtomGit Release 明明发了却查不到 | 该接口按创建时间**升序**返回，别取首项 |
| Gitee 附件传不上去 | `attach_files` 用 `-F file=@<路径>`，不是 `-F file=<base64>` |

更多坑见 `AGENTS.md` §11。
