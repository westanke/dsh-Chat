# DSH Chat — Flutter client for dsh-remote-bridge

一套 Flutter 代码（Android + iOS）实现的聊天客户端，
对话内容来自本机的 [`dsh-remote-bridge`](https://gitee.com/westanke/dsh-remote-bridge)
（协议 `dsh-mobile-v1`）。

> 本工程是**独立实现的客户端 + 自有后端接入**，不是任何第三方官方客户端的分支，
> 不连第三方官方服务器，也不复用任何官方素材（图标、字体、so、混淆资源）。
> 所有分发标识符不含第三方品牌名。

## 快速开始

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
flutter run          # 或 flutter build apk --debug
```

首次启动进「连接到 DSH Bridge」页：填 bridge 地址（如 `http://192.168.1.126:3090`；
真机可先 `adb reverse tcp:3090 tcp:3090` 再填 `http://127.0.0.1:3090`）+ 桌面端
「手机设置 → 远程访问」生成的一次性配对码。配对成功后凭证持久化，之后自动连接。

## 能力

- **对话**：WS `/ws/mobile` 流式增量（`chat.message.delta`）→ `committed` 后重拉历史；
  外部端（REST）写入也会自动刷新。
- **Markdown 严格对称**：标题 / 段落 / 有序无序嵌套列表 / 任务列表 / 粗斜体删除线 /
  行内代码 / 代码块（Atom One Light 高亮 + 语言标签 + 复制）/ 表格（官方通栏表头）/
  引用 / 水平线 / 行内与块级公式 / 链接 / 引用角标。
- **工具调用折叠**：连续工具调用收成一行「执行了命令，读取了文件，已写入文件」，
  点开展开逐条明细（含参数摘要、失败标记、耗时）。
- **思考流**：`已深度思考` 折叠块。
- **深色模式**：跟随系统，两套色板均按官方 App 实测校准。
- **侧边抽屉**：即时搜索 + 日期分组（今天/昨天/更早）+ 设备账号栏。
- **失败可见**：模型限流 / 额度耗尽等 `turn/end` 失败以红色错误条呈现，不静默。

## 文档

| 文件 | 用途 |
|---|---|
| [`../AGENTS.md`](../AGENTS.md) | 工程宪法（红线、目录、token 纪律、协议纪律） |
| [`../docs/design-tokens.md`](../docs/design-tokens.md) | 设计基准（官方 token + 像素实测 + 终验对照） |
| [`../docs/STRUCTURE.md`](../docs/STRUCTURE.md) | 目录/文件清单、bridge 协议引用与协议坑位 |

## 结构（app/lib）

```
design/tokens.dart       全部样式值唯一出口
bridge/gateway.dart      WS 网关（握手、requestId、退避重连、心跳）
bridge/models.dart       协议模型 + 历史事件装配（含过程组折叠与失败解析）
bridge/credentials.dart  凭证持久化       bridge/device.dart  IANA 时区通道
ui/chat_page.dart        聊天主页         ui/chat_state.dart  状态编排
ui/md_view.dart          Markdown 装配    ui/md_code_block.dart 自绘代码块
ui/md_table.dart         自绘表格         ui/message_actions.dart 操作条
ui/process_group.dart    工具调用折叠     ui/sessions_drawer.dart 侧边抽屉
ui/composer.dart         输入条           ui/brand_mark.dart  空态品牌标记
```

## 测试

```sh
flutter test                                  # 24 例
flutter test test/render_mark_test.dart       # 离屏导出品牌标记 PNG
flutter test test/render_md_test.dart         # 离屏导出 Markdown 全家福 PNG
dart run tool/verify_groups.dart              # 宿主侧校验历史装配
dart run tool/verify_err.dart                 # 宿主侧校验失败事件解析
```
