# 本目录是 gpt_markdown 的本地副本（vendor），不是本项目源码。

# 原因
#   gpt_markdown 1.4.1 的 lib/shared_render.dart 里有一个穷尽 switch
#   （switch (Theme.of(context).platform)），缺 TargetPlatform.ohos 分支，
#   在 HarmonyOS 目标上编译报：
#     Error: The type 'TargetPlatform' is not exhaustively matched by the
#     switch cases since it doesn't match 'TargetPlatform.ohos'.
#   上游尚未提供 ohos 支持，故本地保留一份打了一行补丁的副本。

# 改动（仅此一处，补丁可 upstream）
#   lib/shared_render.dart：在 `case TargetPlatform.fuchsia:` 之后增加
#   `case TargetPlatform.ohos:`，让鸿蒙与 Android/iOS/fuchsia 同属
#   「触摸设备 → 表格不画横向滚动条」这一分支。

# 版本
#   上游 gpt_markdown 1.4.1（pub.dev），BSD 风格许可证见本目录 LICENSE
#   （Copyright (c) 2025-2026 Plusfinity AI, Inc. and gpt_markdown contributors）。
#   升级上游版本时：重新解包 → 只重打这一处补丁 → 保留本说明。

example/
test/
CHANGELOG.md
CONTRIBUTING.md
MIGRATION.md
README.md
analysis_options.yaml
