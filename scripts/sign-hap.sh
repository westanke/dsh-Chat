#!/usr/bin/env bash
# 给 Flutter-OH 打出的 unsigned HAP 做本地签名（hap-sign-tool）。
#
# 用法：
#   HAP_KEYSTORE_PWD=... HAP_KEY_PWD=... bash scripts/sign-hap.sh
#   HAP_PROFILE_KIND=debug ... bash scripts/sign-hap.sh
#   bash scripts/sign-hap.sh <in.hap> <out.hap>
#
# 默认读 harmony/signing/ 下的 release 材料：
#   dsh-chat-harmony.p12 + dsh-chat发布证书.cer + dsh-chatRelease发布.p7b
# debug 材料：
#   dsh-chat-harmony.p12 + dsh-chat调试证书.cer + dshchatDebug调试.p7b
#
# 口令只从环境变量读，不写文件、不写日志：
#   HAP_KEYSTORE_PWD  密钥库口令（必填）
#   HAP_KEY_PWD       密钥口令（可选，默认同 HAP_KEYSTORE_PWD）
#   HAP_KEY_ALIAS     别名（默认 dsh-chat-harmony）
#   HAP_PROFILE_KIND  release（默认）/ debug
#   HAP_COMPATIBLE_VERSION 兼容 API（默认 26，与 build-profile.json5 一致）
#   HAP_SIGN_DIR      签名材料目录（默认 harmony/signing）
#   HAP_SIGN_TOOL     hap-sign-tool.jar 路径（默认从 DEVECO_SDK_HOME 推）
#
# 输出默认：artifacts/dsh-Chat-v<version>-harmony.hap
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[32m  ✅ %s\033[0m\n' "$*"; }
bad() { printf '\033[31m  ❌ %s\033[0m\n' "$*" >&2; }

IN="${1:-app/build/ohos/hap/entry-default-unsigned.hap}"
[ -f "$IN" ] || IN="app/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap"

VER=$(grep -oP '^version: \K[0-9]+\.[0-9]+\.[0-9]+' app/pubspec.yaml | head -1)
OUT="${2:-artifacts/dsh-Chat-v${VER}-harmony.hap}"
SIGN_DIR="${HAP_SIGN_DIR:-harmony/signing}"
PROFILE_KIND="${HAP_PROFILE_KIND:-release}"
COMPAT="${HAP_COMPATIBLE_VERSION:-26}"
ALIAS="${HAP_KEY_ALIAS:-dsh-chat-harmony}"

[ -f "$IN" ] || { bad "找不到 unsigned HAP：$IN（先跑 flutter build hap --release --no-codesign）"; exit 1; }
[ -n "${HAP_KEYSTORE_PWD:-}" ] || {
  bad "缺少 HAP_KEYSTORE_PWD。口令在 harmony/signing/README.txt（不要提交/外传）"
  bad "示例：HAP_KEYSTORE_PWD='...' HAP_KEY_PWD='...' bash scripts/sign-hap.sh"
  exit 1
}
KEY_PWD="${HAP_KEY_PWD:-$HAP_KEYSTORE_PWD}"

if [ "$PROFILE_KIND" = "debug" ]; then
  CERT="${HAP_CERT:-$SIGN_DIR/dsh-chat调试证书.cer}"
  PROFILE="${HAP_PROFILE:-$SIGN_DIR/dshchatDebug调试.p7b}"
else
  CERT="${HAP_CERT:-$SIGN_DIR/dsh-chat发布证书.cer}"
  PROFILE="${HAP_PROFILE:-$SIGN_DIR/dsh-chatRelease发布.p7b}"
fi
P12="${HAP_KEYSTORE:-$SIGN_DIR/dsh-chat-harmony.p12}"

for f in "$P12" "$CERT" "$PROFILE"; do
  [ -f "$f" ] || { bad "签名材料缺失：$f"; exit 1; }
done

SDK_HOME="${DEVECO_SDK_HOME:-${DSH_TOOLS:-/media/wangke/OFFICE/workspace/tools}/ohos-sdk/sdk}"
JAR="${HAP_SIGN_TOOL:-$SDK_HOME/default/openharmony/toolchains/lib/hap-sign-tool.jar}"
[ -f "$JAR" ] || { bad "找不到 hap-sign-tool.jar：$JAR（source tools/env.sh 或设 DEVECO_SDK_HOME）"; exit 1; }

JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
command -v "$JAVA_BIN" >/dev/null 2>&1 || JAVA_BIN=java

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

say "签名 HAP：$IN"
say "材料：$P12 / $CERT / $PROFILE（$PROFILE_KIND）"
say "输出：$OUT"

# 口令只经命令行参数传给 JVM；不要把 set -x 打开。
"$JAVA_BIN" -jar "$JAR" sign-app \
  -mode localSign \
  -signAlg SHA256withECDSA \
  -keyAlias "$ALIAS" \
  -keystoreFile "$P12" \
  -keystorePwd "$HAP_KEYSTORE_PWD" \
  -keyPwd "$KEY_PWD" \
  -appCertFile "$CERT" \
  -profileFile "$PROFILE" \
  -inFile "$IN" \
  -outFile "$OUT" \
  -compatibleVersion "$COMPAT"

[ -f "$OUT" ] || { bad "签名没有产出：$OUT"; exit 1; }
SIZE=$(stat -c%s "$OUT")
SHA=$(sha256sum "$OUT" | cut -d' ' -f1)

# HAP 的签名块追加在 ZIP 尾部，`unzip -l` 看不到；必须用 hap-sign-tool 验签。
VERIFY_DIR="$(dirname "$OUT")"
VCHAIN="$VERIFY_DIR/.sign-verify.$$.cer"
VPROFILE="$VERIFY_DIR/.sign-verify.$$.p7b"
VLOG="$VERIFY_DIR/.sign-verify.$$.log"
cleanup_verify() { rm -f "$VCHAIN" "$VPROFILE" "$VLOG"; }
trap cleanup_verify EXIT
if ! "$JAVA_BIN" -jar "$JAR" verify-app \
      -inFile "$OUT" -outCertChain "$VCHAIN" -outProfile "$VPROFILE" >"$VLOG" 2>&1; then
  bad "签名校验失败："
  tail -20 "$VLOG" >&2 || true
  exit 1
fi
ok "签名校验通过（verify-app）"
ok "产物 $OUT"
ok "体积 $SIZE 字节"
ok "SHA-256 $SHA"
