#!/usr/bin/env bash
#
# 鸿蒙版打包脚本 —— 跑双闸门（node 单测 + hvigorw 构建）并把 HAP 归集到 dist/。
#
# 用法：
#   ./scripts/package.sh            # 单测 + 构建 + 归集
#   ./scripts/package.sh --no-test  # 只构建 + 归集（改文案时想快一点）
#
# 说明：
# 1. 工具链环境从 scripts/toolchain-env.sh source（ROOT 可用 DSH_HARMONY_TOOLCHAIN_ROOT
#   覆盖，缺省用与 dsh-companion-harmony 共享的 _toolchain），从任何目录调用都能跑。
# 2. 当前只产出**未签名 HAP**（AGC 证书/Profile 材料未齐，见 build-profile.json5 注释）；
#   材料齐后用 hap-sign-tool 手工双签（docs/RELEASE.md），本脚本无需改动。
# 3. 构建成功标志是 `BUILD SUCCESSFUL`；日志里 `WARN: No signingConfig` 属预期输出。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${PROJECT_DIR}/entry/build/default/outputs/default"
DIST_DIR="${PROJECT_DIR}/dist"

RUN_TEST=1
for arg in "$@"; do
  case "${arg}" in
    --no-test) RUN_TEST=0 ;;
    -h|--help)
      sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "未知参数：${arg}（用 --help 看用法）" >&2
      exit 2
      ;;
  esac
done

# shellcheck disable=SC1091
source "${PROJECT_DIR}/scripts/toolchain-env.sh"

cd "${PROJECT_DIR}"

if [[ "${RUN_TEST}" -eq 1 ]]; then
  echo "==> [1/3] 纯逻辑层单测（node:test + tsx）"
  ( cd test && npm test )
else
  echo "==> [1/3] 跳过单测（--no-test）"
fi

echo "==> [2/3] 构建 HAP（hvigorw assembleHap，未签名）"
mkdir -p "${PROJECT_DIR}/build"
hvigorw assembleHap --no-daemon 2>&1 | tee "${PROJECT_DIR}/build/package-hvigor.log" | grep -E "BUILD (SUCCESSFUL|FAILED)|ERROR|WARN: No signingConfig" || true

if ! grep -q "BUILD SUCCESSFUL" "${PROJECT_DIR}/build/package-hvigor.log"; then
  echo "hvigorw 构建失败（完整日志：build/package-hvigor.log）" >&2
  exit 1
fi

echo "==> [3/3] 归集到 dist/"
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}"/*.hap
cp "${OUT_DIR}"/*.hap "${DIST_DIR}/"
sha256sum "${DIST_DIR}"/*.hap > "${DIST_DIR}/SHA256SUMS.txt"
ls -l "${DIST_DIR}"
echo "✅ 打包完成（未签名；签名步骤见 docs/RELEASE.md）"
