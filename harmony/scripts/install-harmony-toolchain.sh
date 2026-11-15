#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 鸿蒙(HarmonyOS) 命令行工具链安装脚本 —— 全程使用国内镜像源
#
# 用途：在无 DevEco Studio 的 Linux(UOS) 环境下，装齐构建 HAP 所需的：
#   1. JDK 17        （hvigor / 签名工具依赖）
#   2. Node.js 20    （hvigor 构建引擎；本机自带的 24.x 版本过新，hvigor 未必兼容）
#   3. Command Line Tools 5.1.0（华为官方命令行工具包，内含 hvigor / ohpm / hdc / HarmonyOS SDK）
#
# 镜像来源：
#   - Adoptium JDK 17 : 清华 TUNA
#   - Node.js v20     : npmmirror(淘宝)
#   - 命令行工具包     : 华为云 repo.huaweicloud.com（官方镜像，无需登录）
#
# 特性：幂等 + 断点续传。可重复执行，已完成的步骤会跳过。
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="/media/wangke/OFFICE/TRae_work/_toolchain"
DL="$ROOT/downloads"
JDK_DIR="$ROOT/jdk"
NODE_DIR="$ROOT/node"
CLT_DIR="$ROOT/command-line-tools"

# ── 下载地址（全部国内源）────────────────────────────────────────────────────
JDK_URL="https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/linux/OpenJDK17U-jdk_x64_linux_hotspot_17.0.20.1_1.tar.gz"
NODE_URL="https://registry.npmmirror.com/-/binary/node/v20.19.5/node-v20.19.5-linux-x64.tar.gz"
CLT_URL="https://repo.huaweicloud.com/harmonyos/ohpm/5.1.0/commandline-tools-linux-x64-5.1.0.840.zip"
CLT_SHA256="1dcefa4741dc289277560b2802040e0c45b433898d8db453d711d5376e0478f1"

log()  { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[警告] %s\033[0m\n' "$*"; }

mkdir -p "$DL" "$JDK_DIR" "$NODE_DIR"

# ── 通用：带续传与重试的下载 ─────────────────────────────────────────────────
dl() {
  local url="$1" out="$2"
  if [ -s "$out" ] && [ -f "$out.ok" ]; then
    log "已存在，跳过下载：$(basename "$out")"
    return 0
  fi
  log "下载：$url"
  local i
  for i in 1 2 3 4 5; do
    if curl -fL --retry 3 --retry-delay 3 -C - \
        --connect-timeout 20 --max-time 3600 \
        -o "$out" "$url"; then
      touch "$out.ok"
      return 0
    fi
    warn "第 $i 次下载中断，3 秒后续传重试…"
    sleep 3
  done
  echo "下载失败：$url" >&2
  return 1
}

# ── 1. JDK 17 ────────────────────────────────────────────────────────────────
log "步骤 1/3：安装 JDK 17（清华 TUNA / Adoptium）"
if [ -x "$JDK_DIR/current/bin/java" ]; then
  log "JDK 已就绪，跳过"
else
  dl "$JDK_URL" "$DL/jdk17.tar.gz"
  rm -rf "$JDK_DIR"/jdk-17* 2>/dev/null || true
  tar -xzf "$DL/jdk17.tar.gz" -C "$JDK_DIR"
  inner="$(find "$JDK_DIR" -maxdepth 1 -type d -name 'jdk-17*' | head -1)"
  ln -sfn "$inner" "$JDK_DIR/current"
fi
"$JDK_DIR/current/bin/java" -version 2>&1 | head -1

# ── 2. Node.js 20 ────────────────────────────────────────────────────────────
log "步骤 2/3：安装 Node.js 20（npmmirror）"
if [ -x "$NODE_DIR/current/bin/node" ]; then
  log "Node 已就绪，跳过"
else
  dl "$NODE_URL" "$DL/node20.tar.gz"
  rm -rf "$NODE_DIR"/node-v20* 2>/dev/null || true
  tar -xzf "$DL/node20.tar.gz" -C "$NODE_DIR"
  inner="$(find "$NODE_DIR" -maxdepth 1 -type d -name 'node-v20*' | head -1)"
  ln -sfn "$inner" "$NODE_DIR/current"
fi
"$NODE_DIR/current/bin/node" -v

# ── 3. Command Line Tools（含 hvigor / ohpm / hdc / HarmonyOS SDK）────────────
log "步骤 3/3：安装 Command Line Tools 5.1.0（华为云镜像，约 2GB，较慢请耐心）"
if [ -x "$CLT_DIR/bin/hvigorw" ] || [ -d "$CLT_DIR/sdk" ]; then
  log "命令行工具已解压，跳过"
else
  dl "$CLT_URL" "$DL/commandline-tools.zip"
  log "校验 sha256…"
  actual="$(sha256sum "$DL/commandline-tools.zip" | awk '{print $1}')"
  if [ "$actual" != "$CLT_SHA256" ]; then
    echo "sha256 不匹配！期望 $CLT_SHA256，实际 $actual" >&2
    exit 1
  fi
  log "sha256 校验通过，解压中…"
  tmp="$(mktemp -d)"
  unzip -q -o "$DL/commandline-tools.zip" -d "$tmp"
  rm -rf "$CLT_DIR"
  # 解开后通常是一个同名顶层目录，把它归位到 CLT_DIR
  top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [ -d "$top/sdk" ] || [ -d "$top/bin" ]; then
    mv "$top" "$CLT_DIR"
  else
    mkdir -p "$CLT_DIR"; mv "$tmp"/* "$CLT_DIR"/ 2>/dev/null || true
  fi
  rm -rf "$tmp"
fi
log "命令行工具目录结构："
find "$CLT_DIR" -mindepth 1 -maxdepth 1 | sort

# ── 环境文件（供后续构建 source）──────────────────────────────────────────────
ENV="$ROOT/env.sh"
cat > "$ENV" <<EOF
# 由 install-harmony-toolchain.sh 生成：鸿蒙构建环境
export JAVA_HOME="$JDK_DIR/current"
export NODE_HOME="$NODE_DIR/current"
export DEVECO_SDK_HOME="$CLT_DIR/sdk"
export HARMONY_TOOLCHAIN="$CLT_DIR"
export PATH="\$JAVA_HOME/bin:\$NODE_HOME/bin:$CLT_DIR/bin:\$PATH"
# 国内源
export npm_config_registry="https://registry.npmmirror.com"
EOF

log "环境文件已生成：$ENV"
log "全部完成。用法： source $ENV"
