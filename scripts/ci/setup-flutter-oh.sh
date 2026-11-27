#!/usr/bin/env bash
# 统一引导 Flutter-OH SDK（CI 与 release.yml 共用）。
#
# 为什么不能直接 subosito/flutter-action：
#   本仓 material_ui/cupertino_ui 用 CPF ohos fork，代码里有 TargetPlatform.ohos；
#   上游 Flutter 3.50.0 没有这个枚举，Android/iOS/鸿蒙三端都会编译失败。
#
# 本脚本做三件事（幂等）：
#   1) clone OH-Flutter 3.50.0+ohos-1.3.3（已存在则校验 tag）；
#   2) Linux x86_64：把 dart-sdk-url.ohos 的 linux-x64 Dart SDK 与
#      ohos-arm64-release/profile 的 linux-x64 gen_snapshot 指向 CPF 的
#      Dart 3.14.0 工件。官方 OBS 的默认 gen_snapshot 是 3.12.2（kernel 130），
#      与 SDK 的 Dart 3.14.0（kernel 141）不匹配，HAP release 会报
#      "Invalid kernel binary format version (expected 130, found 141)"。
#   3) 导出 FLUTTER_ROOT/PATH（GitHub Actions 下写 GITHUB_ENV/GITHUB_PATH）。
#
# 用法：
#   bash scripts/ci/setup-flutter-oh.sh
#   FLUTTER_OH_TAG=3.50.0+ohos-1.3.3 FLUTTER_OH_ROOT="$HOME/flutter-oh" ...
#
# 说明：macOS 只支持 arm64（OH-Flutter 只发 darwin-arm64 定制 Dart SDK）；
# iOS 构建用的 iOS/macOS 引擎工件由 Google Flutter storage 按 engine.version
# 提供，本脚本不改这些地址。
set -euo pipefail

TAG="${FLUTTER_OH_TAG:-3.50.0+ohos-1.3.3}"
ROOT="${FLUTTER_OH_ROOT:-$HOME/flutter-oh}"
REPO="${FLUTTER_OH_REPO:-https://atomgit.com/oh-flutter/flutter_flutter.git}"
CPF_BASE="${CPF_OHOS_BASE:-https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com/flutter_infra_release/flutter/d55dc4bdf08dd31de6cb88fd8e56c8bccea7656b}"

say() { printf '\033[36m[flutter-oh]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[flutter-oh] %s\033[0m\n' "$*" >&2; exit 1; }

if [ ! -d "$ROOT/.git" ]; then
  # actions/cache 只缓存 `~/flutter-oh/bin/cache`。缓存命中时 restore 会先造出
  # `$ROOT`（里面只有 bin/cache，没有 .git），直接 clone 会因「目录非空」失败
  # （见 GitHub Actions run 46018485205）。先把缓存目录挪开，clone 完再把
  # bin/cache 放回去，既修掉失败又不浪费缓存里的引擎工件。
  restored=""
  if [ -e "$ROOT" ]; then
    restored="${ROOT}.dsh-restored"
    rm -rf "$restored"
    say "$ROOT 已存在但缺少 .git（缓存还原残留），先挪到 $restored"
    mv "$ROOT" "$restored"
  fi
  say "clone $TAG -> $ROOT"
  git clone --depth 1 --branch "$TAG" "$REPO" "$ROOT"
  if [ -n "$restored" ] && [ -d "$restored/bin/cache" ]; then
    rm -rf "$ROOT/bin/cache"
    mv "$restored/bin/cache" "$ROOT/bin/cache"
    say "已复用缓存还原的 bin/cache"
  fi
  [ -z "$restored" ] || rm -rf "$restored"
else
  current="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null || true)"
  [ "$current" = "$TAG" ] || die "$ROOT 已存在但不是 $TAG（当前 ${current:-unknown}）；请删除后重跑"
  say "复用已有 SDK：$ROOT（$TAG）"
fi

URL_FILE="$ROOT/bin/internal/dart-sdk-url.ohos"
[ -f "$URL_FILE" ] || die "缺少 $URL_FILE"

# 只删除本脚本管理的三个键，保留 SDK 自带的 darwin/windows 条目。
TMP_URL="$URL_FILE.dsh-tmp"
for key in \
  'dart-sdk-linux-x64.zip' \
  'ohos-arm64-release/linux-x64.zip' \
  'ohos-arm64-profile/linux-x64.zip'; do
  grep -v "^${key}:" "$URL_FILE" > "$TMP_URL" || true
  mv "$TMP_URL" "$URL_FILE"
done

host_os="$(uname -s)"
host_arch="$(uname -m)"
case "$host_os/$host_arch" in
  Linux/x86_64)
    {
      echo "dart-sdk-linux-x64.zip:${CPF_BASE}/dart-sdk-linux-x64.zip"
      echo "ohos-arm64-release/linux-x64.zip:${CPF_BASE}/ohos-arm64-release/linux-x64.zip"
      echo "ohos-arm64-profile/linux-x64.zip:${CPF_BASE}/ohos-arm64-profile/linux-x64.zip"
    } >> "$URL_FILE"
    say "已覆盖 linux-x64 Dart SDK 与 AOT gen_snapshot（Dart 3.14.0）"
    ;;
  Darwin/arm64)
    say "macOS arm64：使用 SDK 自带的 darwin-arm64 Dart SDK；iOS 引擎走 Google storage"
    ;;
  Darwin/x86_64)
    die "macOS x86_64 没有 OH-Flutter 定制 Dart SDK；请用 macos-15（arm64）runner"
    ;;
  *)
    die "不支持的宿主：$host_os/$host_arch"
    ;;
esac

# Flutter-OH 在含 ohos/ 的项目上执行 pub get/build 时会写 ohos/local.properties，
# 该路径要求 globals.hmosSdk 非空。Android/iOS 构建并不需要真正的 HarmonyOS SDK，
# 这里用最小目录骨架满足探测，避免在 GitHub runner 上装约 7GB 的完整 SDK。
# 真正构建 HAP 的 self-hosted job 必须已有 HOS_SDK_HOME/DEVECO_SDK_HOME，绝不覆盖。
if [ -z "${HOS_SDK_HOME:-}" ] && [ -z "${DEVECO_SDK_HOME:-}" ]; then
  HOS_STUB="$ROOT/.hos-sdk-stub"
  mkdir -p "$HOS_STUB/hmscore" "$HOS_STUB/openharmony"
  export HOS_SDK_HOME="$HOS_STUB"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "HOS_SDK_HOME=$HOS_STUB" >> "$GITHUB_ENV"
  fi
  say "未检测到 HOS SDK：使用空骨架 ${HOS_STUB}（仅 Android/iOS；HAP 需真 SDK）"
fi

export FLUTTER_ROOT="$ROOT"
export PATH="$ROOT/bin:$PATH"

# GitHub Actions：让后续 step 直接拿到 flutter/dart。
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "FLUTTER_ROOT=$ROOT" >> "$GITHUB_ENV"
fi
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$ROOT/bin" >> "$GITHUB_PATH"
fi

say "SDK：$("$ROOT/bin/flutter" --version 2>/dev/null | head -1 || echo 'flutter --version 失败')"
say "Dart：$(dart --version 2>&1 | head -1 || true)"
