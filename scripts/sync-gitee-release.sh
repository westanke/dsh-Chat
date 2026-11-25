#!/usr/bin/env bash
# 把 GitHub Actions Release run 的产物同步到 Gitee Release（国内下载快）。
# 用法: scripts/sync-gitee-release.sh <tag> <github-run-id> [文件名1 文件名2 ...]
#   例: scripts/sync-gitee-release.sh v1.0.14 43669947651 android-apk ios-ipa
# 依赖: git credential 里存有 host=gitee.com 的 token（gitee API 权限 projects/releases）
set -euo pipefail
cd "$(dirname "$0")/.."   # 仓库根

TAG="${1:?用法: $0 <tag> <github-run-id> [artifact名...]}"
RUN_ID="${2:?缺 github run id}"
shift 2
ARTIFACTS=("$@")
[[ ${#ARTIFACTS[@]} -gt 0 ]] || ARTIFACTS=(android-apk ios-ipa)

GITHUB_REPO="${GITHUB_REPO:-westanke/dsh-Chat}"
GITEE_REPO="${GITEE_REPO:-westanke/dsh-Chat}"
API_GH="https://api.github.com/repos/${GITHUB_REPO}"
API_GE="https://gitee.com/api/v5/repos/${GITEE_REPO}"

# token 不回显、不落盘
GH_TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill | sed -n 's/^password=//p')"
GE_TOKEN="$(printf 'protocol=https\nhost=gitee.com\n\n' | git credential fill | sed -n 's/^password=//p')"
[[ -n "$GH_TOKEN" && -n "$GE_TOKEN" ]] || { echo "git credential 缺 github/gitee token" >&2; exit 1; }

mkdir -p artifacts
TMP="$(mktemp -d "artifacts/.tmp-sync-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# 1) 下载 GitHub artifacts 并解出产物
mkdir -p "$TMP/assets"
for NAME in "${ARTIFACTS[@]}"; do
  ID="$(curl -sf -H "Authorization: Bearer $GH_TOKEN" "$API_GH/actions/runs/$RUN_ID/artifacts" \
        | python3 -c "import json,sys; print(next(a['id'] for a in json.load(sys.stdin)['artifacts'] if a['name']=='$NAME'))")"
  curl -sfL -H "Authorization: Bearer $GH_TOKEN" -o "$TMP/$NAME.zip" "$API_GH/actions/artifacts/$ID/zip"
  unzip -o -q "$TMP/$NAME.zip" -d "$TMP/assets"
done
ls -lh "$TMP/assets"

# 2) 建/复用 gitee release（tag 必须已推到 gitee）
REL_ID="$(curl -s -H "Authorization: token $GE_TOKEN" "$API_GE/releases/tags/$TAG" | python3 -c "
import json,sys
try: print(json.load(sys.stdin)['id'])
except Exception: print('')")"
if [[ -z "$REL_ID" ]]; then
  VER="${TAG#v}"
  REL_ID="$(curl -s -X POST -H "Authorization: token $GE_TOKEN" -H 'Content-Type: application/json' \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"$TAG\",\"target_commitish\":\"main\",\"body\":\"dsh-Chat $VER 发版（Android APK arm64 + iOS 未签名 IPA）\"}" \
    "$API_GE/releases" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
fi
echo "gitee release id=$REL_ID"

# 3) 清旧附件再传新（幂等：重复跑不堆积旧版本文件）
for AID in $(curl -s -H "Authorization: token $GE_TOKEN" "$API_GE/releases/$REL_ID/attach_files" | python3 -c "
import json,sys
print(' '.join(str(a['id']) for a in json.load(sys.stdin)))"); do
  curl -s -X DELETE -H "Authorization: token $GE_TOKEN" "$API_GE/releases/$REL_ID/attach_files/$AID" >/dev/null
done

# 注意端点是下划线 attach_files（连字符 attach-files 404）；勿手动设 Content-Type（会覆盖 multipart boundary）
for F in "$TMP/assets"/*; do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: token $GE_TOKEN" -F "file=@$F" \
    "$API_GE/releases/$REL_ID/attach_files")"
  [[ "$CODE" == 200 || "$CODE" == 201 ]] || { echo "上传失败 $F: HTTP $CODE" >&2; exit 1; }
  echo "✓ $(basename "$F")"
done
echo "完成: https://gitee.com/${GITEE_REPO}/releases/tag/$TAG"
