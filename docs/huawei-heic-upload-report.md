# 华为手机 HEIC 图片无法上传 —— 调查报告

> 2026-11-10。反馈来源：用户 (m00001)「@dsh-Chat/ 华为手机无法上传图片」，
> 后续收窄 (m00156)「主要是HEIC传不了」。
> 本仓工程宪法 `AGENTS.md` §9：未装机验证过的功能不许写「已完成」；本报告的验证边界见 §7。

---

## 1. 现象与结论摘要

| 项 | 内容 |
|---|---|
| 症状 | 华为/荣耀手机选图后无法作为图片发送（用户确认主要是 HEIC）。vivo V2080A 上正常。 |
| 直接原因 | 客户端**按文件名扩展名**判类型，白名单只有 `png/jpg/jpeg/webp/gif` 五种；HEIC（`.heic`/`.heif`）不在其中，被「仅支持 PNG/JPEG/WebP/GIF 图片」当场拦下。 |
| 深层原因 | ① 判据本身错误：类型应由**字节魔数 / MIME** 决定，而不是 `OpenableColumns.DISPLAY_NAME` 的扩展名（华为图库 DISPLAY_NAME 常无扩展名、纯数字、或缺省为 `image`）；② 即使放开白名单直接发 `image/heic`，内核也不收——内联 prompt 的 `imageLimits.mediaTypes` 是 `Object.freeze` 死字面量，只有 4 种。 |
| 正确修法 | 选图在 **Kotlin 原生侧**按字节魔数嗅探真实类型 → 不在内核 4 种白名单的（HEIC/HEIF/BMP/AVIF）用 `BitmapFactory` 客户端**转码**成 JPEG（无 alpha）/ PNG（有 alpha）再发；同时把「按扩展名判类型」改为「回传真实 mediaType」，去掉 DISPLAY_NAME 依赖，补读权限 flag、安全文件名、明确错误回传。 |
| 与姊妹仓一致性 | 与 `dsh-companion` issue #17 的裁定完全一致（`ChatContentParts.kt` / `ImageTranscoder.kt` 已实现并装机验证过同一套口径）。 |

---

## 2. 调查对象与环境约束（务必先读）

- **无华为真机**：`adb devices` 仅一台 vivo V2080A（Android 11 / sdk30，未装 dsh-Chat），无华为/荣耀设备、无华为日志/崩溃记录。本结论是**代码 + 协议 + 兼容性调研**定位，不是真机复现。
- **环境变化（调查中途）**：调研阶段 `/dev/sda` 一度以 `ro` 挂载、`sudo` 因 nosuid 失效，原仓无法写；因此在 `/media/wangke/OFFICE/workspace/.dsh-mobile/dsh-Chat`（工作树快照，含 `composer.dart` 已有的 `_slashMatches` take(6)→全量未提交修正）中完成修改与验证。实施尾声挂载恢复 `rw`，**修复已直接同步回原仓 `/media/wangke/OFFICE/workspace/dsh-Chat` 并在原仓复验通过**（§7）。副本仅作验证沙箱，不再是交付物。
- **工具链**：Flutter 3.47.9 / Dart 3.13.7，`minSdk=24 / compileSdk=36`（`FlutterExtension.kt:23,26,34`）。原 SDK 启动器首跑会写 `engine.stamp.tmp`/`engine.realm`、遥测会删 `.dart-tool/*.log`，只读盘均失败；已把 SDK（2.3G）与 `dsh-home`（含 pub-cache，369M）复制到可写区后打通，原仓复验复用该工具链。Kotlin 侧**无 kotlinc / gradle 命令**，只能人工核对 + 照搬 companion 已验证代码，**无法编译验证**（见 §7）。

---

## 3. 上传链路（修复前，读代码还原）

```
Composer「+」(composer.dart:351 _pickImage)
  → DshPlatform.pickImage()            (bridge/platform.dart:52-66, MethodChannel 'dsh/platform')
  → MainActivity ACTION_GET_CONTENT    (MainActivity.kt:74-92, image/* + CATEGORY_OPENABLE)
  → onActivityResult: openInputStream → 读 bytes → queryDisplayName(DISPLAY_NAME)
                      → 写 cacheDir/"pick-$name" → 回 {path, name}   (MainActivity.kt:239-273)
  → 【扩展名白名单校验 #1】composer.dart:353-358  name.split('.').last → 5 种
  → pickComposerImage()               (composer_widgets.dart:100-112)
       【扩展名白名单校验 #2】_composerImageWhitelist[ext] → mediaType
       → File(path).readAsBytes() → base64Encode → 暂存 _pendingImage
  → _send(): 8MiB 检查 → PromptPart.image(mediaType, base64, name:)  (composer.dart:323-349)
  → ChatState.sendWithImage → GatewayApi.sendText(contentParts)       (gateway_api.dart:137-154)
  → GatewayClient.request('message') 经 WS /ws/mobile → bridge → 内核 sessions.prompt
```

- 协议侧 `dsh-remote-bridge/src/host/routes/shared.ts:167-176` `readPromptContent` 对 `type=image` 只校验 `mediaType`/`data` 是 string，**不限制取值**；`chat-adapter.ts:846-872` 原样把 `content: parts` 交给内核。
- 内核 `@deepseek-ai/dsh-attachment-local/lib/index.js:998-1009`（一手证据，本机 5 处安装之一）：

  ```js
  this.imageLimits = Object.freeze({
    maxImageBytes: config.maxImageBytes ?? 20971520,
    maxImagesPerMessage: config.maxImagesPerMessage ?? 20,
    maxMessageImageBytes: config.maxMessageImageBytes ?? 209715200,
    maxImagePixels: config.maxImagePixels ?? 64e6,
    maxImageDimension: config.maxImageDimension ?? 8192,
    mediaTypes: Object.freeze(["image/png","image/jpeg","image/webp","image/gif"]),
  });
  ```

  `mediaTypes` 是**死字面量、无 config 入口**。任何不在此集合的 mediaType 在用户点发送之后被内核拒（`INVALID_IMAGE` / "Unsupported or malformed image data."）。

> 注：bridge 的 `src/host/image-handoff.ts:109` / `attachments.ts:56-64` / `sniffMediaType` 里出现 heic/heif/bmp/avif，**只是纯文本模型的 handoff 落盘路径**的扩展名表与魔数表，不是内联 prompt 的收图白名单；`mapImagesToHandoff` 仅对 `modelIsConfirmedTextOnly` 生效。据此误判「服务端已支持 HEIC、客户端补白名单即可」是错的，已在本次调研中纠正。

---

## 4. 逐条根因与协议依据

### 4.1 【主因】HEIC 被客户端扩展名白名单拒之门外

- `app/lib/ui/composer.dart:128-135` 与 `app/lib/ui/composer_widgets.dart:88-95` 各有一份 5 种扩展名白名单：
  `{'png':'image/png','jpg':'image/jpeg','jpeg':'image/jpeg','webp':'image/webp','gif':'image/gif'}`。
- `composer.dart:353-358` 取 `picked['name']!.split('.').last`，不在白名单 → `SnackBar('仅支持 PNG/JPEG/WebP/GIF 图片')` 直接 return。
- 华为/荣耀相册默认「高效照片」HEIC（`.heic`/`.heif`），扩展名不在表内 → 必然被拦。这与用户「主要是HEIC传不了」完全吻合。
- 姊妹仓 `dsh-companion/…/ImageTranscoder.kt` 注释亦明确：「用户手里最常见的手机原图恰恰是 HEIC（华为/荣耀『高效格式』、iPhone 默认）」。

### 4.2 【判据错误】按 DISPLAY_NAME 扩展名判类型，在华为上本就不可靠

- `MainActivity.kt:267-273` `queryDisplayName(uri)` 查 `OpenableColumns.DISPLAY_NAME`，取不到回落字符串 `"image"`（无扩展名）；`composer.dart` 再对它 `split('.').last`。
- 华为图库返回 `content://media/...`，文件选择器返回 `content://...documents/document/image%3A...`，DISPLAY_NAME 常表现为**纯数字 ID、无后缀、含目录片段或 null**（MAUI 框架级单测、国内多篇机型适配记录、华为开发者论坛均记录「没有找到文件后缀」）。此时即使图片本体是 JPEG，也会因取不到 `.jpg` 被误拒。
- 证据等级区分：
  - **框架级实证**：[dotnet/maui PR #35050 diff](https://github.com/dotnet/maui/commit/c28135bc806c2185f9ea95e869ada27479d6723d.patch)（DISPLAY_NAME 可为无扩展名/null/含目录，附单测）。
  - **机型适配记录（标题级佐证）**：[华为 URI 差异 ①](https://www.cnblogs.com/Sharley/p/9346550.html)、[②](https://blog.csdn.net/geofferysun/article/details/53432945)、[Photo Picker 纯数字 URI](https://www.cnblogs.com/kaimingkai/p/19147237)、[华为论坛「没有找到文件后缀」](https://developer.huawei.com/consumer/cn/forum/topic/0207227442175260115)。
  - **分区存储/权限背景**：[CommonsWare durable access](https://commonsware.com/blog/2019/10/27/scoped-storage-stories-durable-access.html)、[SAF basics](https://commonsware.com/blog/2019/10/19/scoped-storage-stories-saf-basics.html)、[阿里云权限对照](https://developer.aliyun.com/article/1770946)。
  - **官方 API**：[ContentResolver.getType(Uri)](https://developer.android.com/reference/android/content/ContentResolver#getType(android.net.Uri))、[OpenableColumns](https://developer.android.google.cn/reference/android/provider/OpenableColumns)。
  - 上述不依赖真机即可成立：**判类型不能靠文件名**，应靠字节魔数（或 `contentResolver.getType` 作辅助）。

### 4.3 【不能简单补白名单】内核只收 4 种，HEIC 必须转码

- 见 §3 内核 `imageLimits.mediaTypes` 一手证据。放开 `image/heic` 直发会在**点发送之后**被内核拒，且错误信息在服务端、用户无感，比当场提示更糟。
- `dsh-companion/…/ChatContentParts.kt:191-196`（成熟口径，装机验证过）：
  `val SUPPORTED_IMAGE_MEDIA_TYPES: Set<String> = setOf("image/png","image/jpeg","image/webp","image/gif")`；`needsTranscode(mediaType) = !isSupportedImageMediaType(mediaType)`；注释指出「报错在用户点发送之后，故必须在选图那一刻客户端校验」。
- 正确做法：`dsh-companion/…/ImageTranscoder.kt:36-127` —— 客户端 `BitmapFactory.decodeByteArray` 解码 HEIC → `Bitmap.compress` 重编码为 JPEG/PNG：
  - `MAX_DECODE_PIXELS = 4096L*4096L` 仅防 OOM 降采样（**格式转换，非压缩**；issue #15 已裁定禁止为塞 WS 帧无谓重编码）；
  - `targetMediaType(hasAlpha) = if (hasAlpha) "image/png" else "image/jpeg"`（一律 PNG 会让 8MiB HEIC 变几十 MB 撞 `composer.dart:332-339` 的 8MiB 上限）；
  - `JPEG_QUALITY = 90`，`decoded.recycle()` 防泄漏。
- 字节魔数表直接对齐 `dsh-remote-bridge/src/host/image-handoff.ts:165-189` `sniffMediaType`：PNG `89 50 4E 47 0D 0A 1A 0A`、JPEG `FF D8 FF`、GIF87a/GIF89a、RIFF@0+WEBP@8、BMP `42 4D`、`ftyp`@4 且 brand@8 `avi*`→avif / `hei*|hev*|mif*`→heic。

### 4.4 【可感知性缺陷】失败全程静默，用户「点了没反应」

- `MainActivity.kt:239-265`：`openInputStream` 失败、`bytes==null`、写缓存异常，**任何 catch 都 `result.success(null)`**；`platform.dart:52-66` 把 PlatformException/MissingPluginException 也吞成 `null`；`composer.dart:353` `if (picked == null) return` 无任何提示。
- 用户描述「无法上传」很可能混有这一类：读 URI 失败时完全无反馈。修法：失败回传明确 `error` 文案，由 `_pickImage` 弹 SnackBar。

### 4.5 【健壮性】权限 flag 与缓存文件名

- `MainActivity.kt:74-92` 的 `ACTION_GET_CONTENT` 未加 `Intent.FLAG_GRANT_READ_URI_PERMISSION`。虽然 `ACTION_GET_CONTENT` 的 `data` URI 通常自带临时读授权，但部分 DocumentsProvider / 华为实现下补上此 flag 更稳妥（[getType 官方](https://developer.android.com/reference/android/content/ContentResolver#getType(android.net.Uri)) / CommonsWare 同背景）。
- `MainActivity.kt:259` `File(cacheDir, "pick-$name")` 直接拼接 DISPLAY_NAME：若其含 `/`、为空或为 `"image"`，会生成异常/无扩展名路径。同文件 `openFile` 分支 `MainActivity.kt:208-210` 已有净化范式可复用：`name.substringAfterLast('/').replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5]"), "_")`。修法：缓存名按**嗅探出的 mediaType 生成固定扩展名**，不依赖 DISPLAY_NAME。

---

## 5. 修复方案（已落地到原仓，见 §7 / §8）

### Kotlin 侧（`app/android/app/src/main/kotlin/com/dsh/dshchat/`）

1. Intent 加 `Intent.FLAG_GRANT_READ_URI_PERMISSION`。
2. 新增 `ImagePickHelper.kt`（不塞进 MainActivity，避免超 500 行、职责清晰）：
   - `sniffMediaType(bytes): String?` —— 照 §4.3 魔数表；
   - `supportedMediaTypes`（4 种）、`extensionFor(mediaType)`；
   - `prepare(bytes, limitBytes): Prepared` —— 4 种白名单内原样返回，否则走私有 `transcode`（照 `ImageTranscoder.kt`：bounds 读尺寸 → `inSampleSize` → decode → `hasAlpha()` 选 PNG/JPEG → compress(90) → 超限 TooLarge → recycle），返回 `Success(mediaType, extension)` 或 `Failure(中文原因)`；
   - `cacheFileName(extension)`（不拼 DISPLAY_NAME）+ `displayName(raw, mediaType)`（净化 + 真实扩展名）。
3. `MainActivity.onActivityResult`：读字节 → 嗅探 → 需要则转码 → 写安全缓存 → 回传 `{path, name, mediaType}`；失败回传 `{error: 中文原因}`（不再静默 null）。8MiB 上限在原生侧与 Dart 侧一致。

### Dart 侧（`app/lib/`）

1. 新增 `bridge/image_media_type.dart` 纯函数（可单测、平台无关兜底）：
   `sniffImageMediaType(List<int> bytes)`（同魔数表）、`supportedImageMediaTypes`（4 种）、`isSupportedImageMediaType()`、`mediaTypeExtension()`。
2. `bridge/platform.dart`：回传 Map 接受并透传 `mediaType` / `error` 字段。
3. `ui/composer.dart`：`_pickImage` 去掉扩展名白名单；`error` 有值则弹明确提示；否则用回传 `mediaType`（缺失时用 `sniffImageMediaType` 读缓存字节兜底）做 4 种白名单校验。删 `_imageWhitelist`。
4. `ui/composer_widgets.dart`：`pickComposerImage` 去掉 `_composerImageWhitelist`，直接使用回传/兜底 mediaType + base64。
5. 新增 `app/test/image_media_type_test.dart`：PNG/JPEG/GIF/WEBP/HEIC(ftyp)/BMP/AVIF/未知字节的嗅探 + 白名单判定 + 边界（短数组、截断 ftyp）单测。

### 文档同步

`docs/STRUCTURE.md`：`bridge/image_media_type.dart` 新条目、`bridge/platform.dart` / `ui/composer.dart` / `ui/composer_widgets.dart` / 平台侧 `MainActivity.kt` / `ImagePickHelper.kt` 口径更新、`app/test/` 表新增 `image_media_type_test.dart`（`scripts/ci/docs-check.sh` 机检要求 lib/ 每个 .dart 都被登记）。

---

## 6. 与宪法 / 姊妹仓的一致性

- 未改协议、未私自兼容魔改 bridge（宪法 §5）；转码口径与 `dsh-companion` issue #17 一致，不是照抄三仓职责。
- `lib/` 新增文件只落在既有 `bridge/` 子目录（§3）；单文件均 ≤500 行（§7）；禁 print/dynamic（§7）。
- 改 `lib/` 同提交改 `docs/STRUCTURE.md`（§8）。
- 产物标识符零 deepseek；对外表述不写「已完成」装机验收（§9）。

---

## 7. 验证边界（如实标注，宪法 §9）

| 项 | 结果 |
|---|---|
| `bash scripts/ci/docs-check.sh` | ✅ 通过（原仓，文档契约三检全绿：lib/ 全登记 / 无死链 / 无旧仓名） |
| `flutter pub get` | ✅ 通过（原仓，复用可写区 SDK + HOME） |
| `flutter analyze` | ✅ **No issues found!**（原仓；宪法 §7 warning/info 零积压） |
| `flutter test` | ✅ **125 项全过**（原仓，含新增 `image_media_type_test.dart` 的魔数嗅探/白名单/边界单测） |
| Kotlin 编译 | **未验证**：本机无 kotlinc/gradle 命令，只人工核对 + 照搬 companion 已装机验证过的实现 |
| 真机（华为/荣耀）上传 HEIC | **未验证**：无华为真机，需装机后由用户回归 |
| vivo 回归（JPEG 仍可发、无回退） | **未验证**：需装机回归 |

> 因此本修复的表述为「代码级修复 + Dart 侧自动验证全绿」，**不是「已装机验证完成」**。

---

## 8. 落地状态与回归指引

- 修复已**直接写入原仓** `/media/wangke/OFFICE/workspace/dsh-Chat`（挂载恢复 `rw` 后同步 9 个文件），并在原仓跑通四步复验（§7）。当前 `git status --short`：5 个修改 + 4 个新文件（`MainActivity.kt` / `ImagePickHelper.kt` / `platform.dart` / `image_media_type.dart` / `composer.dart` / `composer_widgets.dart` / `image_media_type_test.dart` / `STRUCTURE.md` / `huawei-heic-upload-report.md`），**未提交、未推送**。
- 按宪法 §10，**不 push / 不 release / 不 tag / 不上传产物**未经用户明确同意；本地 commit 可由用户决定（提交信息建议 `fix(image): 华为 HEIC 上传按字节魔数判类型并客户端转码`）。
- 真机回归（需用户）：① 华为/荣耀「高效照片」HEIC 选图能转码并发出；② 华为图库返回无扩展名/纯数字 DISPLAY_NAME 的 JPEG 仍能发；③ vivo 常规 JPEG 无回退；④ 转码大图不 OOM、不撞 8MiB；⑤ 读 URI 失败时弹明确中文提示而非静默。
- 构建产物不入库（`app/build/` 等已在 `.gitignore`）；`ref/mark-preview.png` / `ref/md-preview.png` 是 `flutter test` 渲染测试生成的派生产物，按需清理。

---

## 9. 关键来源索引

- 内核白名单一手证据：`@deepseek-ai/dsh-attachment-local/lib/index.js:998-1009`（本机路径见 §2 环境调查，5 处安装）。
- 本仓源码：`app/android/app/src/main/kotlin/com/dsh/dshchat/MainActivity.kt:74-92,239-273`、`app/lib/bridge/platform.dart:52-66`、`app/lib/ui/composer.dart:128-135,323-366`、`app/lib/ui/composer_widgets.dart:88-112`、`app/lib/bridge/content.dart:94-119`。
- 服务端：`dsh-remote-bridge/src/host/routes/shared.ts:167-176`、`chat-adapter.ts:846-872`、`image-handoff.ts:109-189`、`bridge/attachments.ts:56-64`。
- 姊妹仓成熟口径：`dsh-companion/app/src/main/java/io/github/westanke/dshcompanion/data/ChatContentParts.kt:175-295`、`ImageTranscoder.kt:36-127`。
- 外部：[MAUI #35050](https://github.com/dotnet/maui/commit/c28135bc806c2185f9ea95e869ada27479d6723d.patch)、[华为 URI ①](https://www.cnblogs.com/Sharley/p/9346550.html)、[②](https://blog.csdn.net/geofferysun/article/details/53432945)、[Photo Picker 数字 URI](https://www.cnblogs.com/kaimingkai/p/19147237)、[华为论坛无后缀](https://developer.huawei.com/consumer/cn/forum/topic/0207227442175260115)、[CommonsWare durable](https://commonsware.com/blog/2019/10/27/scoped-storage-stories-durable-access.html)、[SAF basics](https://commonsware.com/blog/2019/10/19/scoped-storage-stories-saf-basics.html)、[阿里云权限对照](https://developer.aliyun.com/article/1770946)、[getType](https://developer.android.com/reference/android/content/ContentResolver#getType(android.net.Uri))、[OpenableColumns](https://developer.android.google.cn/reference/android/provider/OpenableColumns)。
