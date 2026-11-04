#!/usr/bin/env bash
# dsh-Chat 一键发版（两阶段）：准备 → 提交 → 发布。范式抄自姊妹仓 dsh-companion。
#
# ## 为什么是两阶段
#
# 打包后 README 会被回填真实数字（体积/SHA-256），这批改动必须先提交，
# tag 才能指向「文档与产物一致」的提交 —— 否则 tag 里是旧文档
# （正是「文档描述一个不存在的状态」）。所以：
#
#   bash scripts/release.sh                 # 阶段 A：检查 → 门禁 → 打包 → 回填
#   git add … && git commit …               # 人工提交（README 数字已填好）
#   bash scripts/release.sh --publish       # 阶段 B：tag → 双推 → 两站 Release → 回读
#
# ## 从姊妹仓抄来的教训（全部已内建为闸门）
#
# - README 双站漂移：阶段 A 回填后自检版本号唯一性。
# - Gitee 创建 Release 的 access_token 必须挂 query 不进 JSON body（v2.2.47 报 40001）。
# - tag 内 artifacts/SHA256SUMS.txt 必须与产物 cmp 一致（桥仓 v2.6.0 踩过分叉）。
# - 下载回读的 APK SHA 必须与本地一致（防「传了个旧包」）。
#
# 凭据：从 ~/.config/dsh-git/tokens.conf 读（本机三平台 token 都在那），
# 不依赖 ~/.git-credentials。
#
# 用法：
#   bash scripts/release.sh                 # 阶段 A
#   bash scripts/release.sh --publish       # 阶段 B
#   DRY_RUN=1 …                             # 只打印计划
#   SKIP_CHECK=1 …                          # 跳过门禁（已在别处跑过）
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="prepare"
[ "${1:-}" = "--publish" ] && MODE="publish"
DRY_RUN=${DRY_RUN:-0}

say() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[32m  ✅ %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m  ⚠️ %s\033[0m\n' "$*"; }
bad() { printf '\033[31m  ❌ %s\033[0m\n' "$*"; }
run() { if [ "$DRY_RUN" = "1" ]; then say "  [dry] $*"; else "$@"; fi; }

# 版本取自 pubspec.yaml 的 version: <name>+<code>（tag 不能带 +，tag=v<name>）。
PUBSPEC="app/pubspec.yaml"
VER=$(grep -oP '^version: \K[0-9]+\.[0-9]+\.[0-9]+' "$PUBSPEC" | head -1)
CODE=$(grep -oP '^version: [0-9.]+\+\K[0-9]+' "$PUBSPEC" | head -1)
TAG="v${VER}"
APK_NAME="dsh-Chat-${TAG}.apk"
APK="artifacts/${APK_NAME}"
REPO_GITEE="westanke/dsh-Chat"
REPO_ATOMGIT="westanke163/dsh-Chat"
FLUTTER="${FLUTTER:-/media/wangke/OFFICE/workspace/tools/flutter/bin/flutter}"

[ -n "$VER" ] && [ -n "$CODE" ] || { bad "没能从 $PUBSPEC 解析 version"; exit 1; }

# ══════════════════════════════════════════════════════════════════
if [ "$MODE" = "prepare" ]; then
  say "═══ 阶段 A · 准备 ${TAG}（versionCode ${CODE}）═══"
  say ""

  say "0) 前置检查"
  [ -n "$(git status --porcelain)" ] && warn "工作区有待提交改动（阶段 A 允许，阶段 B 会再查）" || ok "工作区干净"
  ok "version $VER+$CODE / tag $TAG"
  say ""

  if [ "${SKIP_CHECK:-0}" != "1" ]; then
    say "1) 门禁（docs-check + analyze + test）"
    run bash scripts/ci/docs-check.sh
    (cd app && run "$FLUTTER" analyze --no-fatal-infos --no-fatal-warnings)
    (cd app && run "$FLUTTER" test)
    ok "门禁通过"
  else
    say "1) 门禁 —— 已按 SKIP_CHECK=1 跳过"
  fi
  say ""

  say "2) 打包 flutter build apk --release"
  (cd app && run "$FLUTTER" build apk --release)
  SRC="app/build/app/outputs/flutter-apk/app-release.apk"
  [ -f "$SRC" ] || SRC="app/build/outputs/flutter-apk/app-release.apk"
  if [ "$DRY_RUN" != "1" ]; then
    [ -f "$SRC" ] || { bad "没找到 $SRC"; exit 1; }
    mkdir -p artifacts
    cp "$SRC" "$APK"
    SIZE=$(stat -c%s "$APK")
    SHA=$(sha256sum "$APK" | cut -d' ' -f1)
    ok "产物 $APK_NAME"
    ok "体积 $SIZE 字节"
    ok "SHA-256 $SHA"
  else
    SIZE=0; SHA="(dry)"; say "  [dry] 复制并计算指纹"
  fi
  say ""

  say "3) 回填真实数据（README + SHA256SUMS）"
  if [ "$DRY_RUN" = "1" ]; then
    say "  [dry] 跳过回填"
  else
    python3 scripts/backfill-release.py "$VER" "$CODE" "$SIZE" "$SHA" "$APK_NAME"
    {
      echo "# dsh-Chat 产物校验（${TAG}）"
      echo "$SHA  $APK_NAME"
    } > artifacts/SHA256SUMS.txt
    ok "已写 artifacts/SHA256SUMS.txt"

    # 自检：README 里不该残留其它版本徽章数字（历史记录行除外）。
    mix=$(grep -oE "badge/version-[0-9.]+" README.md | sort -u | grep -v "version-${VER}$" || true)
    [ -n "$mix" ] && warn "README 徽章版本不唯一：$mix"

    say ""
    say "接下来（人工）："
    say "  1) 校对 README 的文字描述（数字已自动填）"
    say "  2) git add README.md artifacts/ → git commit"
    say "  3) bash scripts/release.sh --publish"
  fi
  exit 0
fi

# ══════════════════════════════════════════════════════════════════
say "═══ 阶段 B · 发布 ${TAG} ═══"
say ""

say "0) 前置检查"
if [ -n "$(git status --porcelain)" ]; then
  bad "工作区有未提交改动 —— 先提交，否则 tag 会指向一个文档还没更新的提交"
  git status --short | head -10
  exit 1
fi
[ -f "$APK" ] || { bad "没有产物 $APK —— 先跑阶段 A"; exit 1; }
SIZE=$(stat -c%s "$APK")
SHA=$(sha256sum "$APK" | cut -d' ' -f1)
ok "工作区干净、产物存在（$SIZE 字节）"

# 产物指纹必须与 README 一致，否则就是「文档描述另一个包」。
if grep -q "$SHA" README.md; then
  ok "README 的 SHA-256 与产物一致"
else
  bad "README 里的 SHA-256 与产物不符 —— 回填没做完"
  exit 1
fi

# token 从本机 dsh-git 凭据读。构建期常把 HOME 覆盖到 tools/dsh-home
# （flutter 遥测只读文件系统会炸），所以同时兜底真实家目录的绝对路径。
for CONF_HOME in "$HOME" "/home/wangke"; do
  if [ -f "$CONF_HOME/.config/dsh-git/tokens.conf" ]; then
    TOKENS_CONF="$CONF_HOME/.config/dsh-git/tokens.conf"; break
  fi
done
GT=$([ -n "${TOKENS_CONF:-}" ] && grep -m1 '^gitee\.com ' "$TOKENS_CONF" | sed -E 's/.*token=([A-Za-z0-9]+).*/\1/' || true)
AT=$([ -n "${TOKENS_CONF:-}" ] && grep -m1 '^atomgit\.com ' "$TOKENS_CONF" | sed -E 's/.*token=([A-Za-z0-9]+).*/\1/' || true)
[ -n "$GT" ] && ok "Gitee token 就绪" || warn "没有 Gitee token，Release 会跳过"
[ -n "$AT" ] && ok "AtomGit token 就绪" || warn "没有 AtomGit token，Release 会跳过"
say ""

say "1) 打 tag $TAG"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  ok "本地已有 $TAG，跳过"
else
  # HOME 覆盖后 git 探测不到身份（tag 也要署名），显式沿用仓库 config。
  TAG_NAME=$(git config user.name) TAG_EMAIL=$(git config user.email)
  [ -n "$TAG_NAME" ] && [ -n "$TAG_EMAIL" ] || { bad "git 身份未配置（user.name/user.email）"; exit 1; }
  run git -c user.name="$TAG_NAME" -c user.email="$TAG_EMAIL" tag -a "$TAG" -m "dsh-Chat ${VER}+${CODE}"
  [ "$DRY_RUN" = "1" ] || ok "已创建 $TAG"
fi
# tag 指向的树必须包含当前这份 SHA256SUMS.txt（防 tag 校验值与附件分叉，桥仓 v2.6.0 踩过）。
if [ "$DRY_RUN" != "1" ] && ! git show "$TAG:artifacts/SHA256SUMS.txt" 2>/dev/null \
     | cmp -s - artifacts/SHA256SUMS.txt; then
  bad "$TAG 里的 artifacts/SHA256SUMS.txt 与产物不一致 —— 中止（tag 未推送）"
  bad "  修法：git tag -d $TAG，重跑阶段 A 回填并提交，再跑 --publish"
  exit 1
fi
[ "$DRY_RUN" = "1" ] || ok "tag 内容校验通过（SHA256SUMS.txt 与产物一致）"
say ""

say "2) git 双推（复用 push-all.sh，分支 + tag）"
if [ "$DRY_RUN" = "1" ]; then
  say "  [dry] PUSH_TAGS=1 bash scripts/push-all.sh"
else
  PUSH_TAGS=1 bash scripts/push-all.sh
  ok "双推完成"
fi
say ""

say "3) 两站 Release + APK 附件"
gitee_release() {
  [ -z "$GT" ] && { warn "无 Gitee token，跳过"; return 0; }
  local id
  id=$(curl -s "https://gitee.com/api/v5/repos/$REPO_GITEE/releases/tags/$TAG?access_token=$GT" \
       | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('id',''))
except Exception: print('')" 2>/dev/null || true)
  if [ -z "$id" ]; then
    say "  创建 Gitee Release $TAG…"
    [ "$DRY_RUN" = "1" ] && return 0
    local payload
    payload=$(VER="$VER" TAG="$TAG" APK_NAME="$APK_NAME" SIZE="$SIZE" SHA="$SHA" python3 -c '
import json, os
tag = os.environ["TAG"]; apk = os.environ["APK_NAME"]
size = int(os.environ["SIZE"]); sha = os.environ["SHA"]
body = "\n".join([
    "## " + tag, "",
    "- 产物：`" + apk + "`，**{:,} 字节**".format(size),
    "- SHA-256：`" + sha + "`", "",
    "变更详情见仓库提交记录；协议要求 dsh-remote-bridge ≥ 2.10.0（hello.protocol=3）。",
])
print(json.dumps({"tag_name": tag, "name": os.environ["VER"],
                  "body": body, "target_commitish": "main"}))
')
    # access_token 必须挂 query 不进 JSON body（companion v2.2.47 踩过 40001）。
    id=$(curl -s -X POST "https://gitee.com/api/v5/repos/$REPO_GITEE/releases?access_token=$GT" \
         -H 'Content-Type: application/json' -d "$payload" \
         | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('id',''))
except Exception: print('')")
    [ -n "$id" ] && ok "Gitee Release 已建（id $id）" || { bad "Gitee Release 建失败"; return 1; }
  else
    ok "Gitee Release 已存在（id $id），跳过创建"
  fi
  local have
  have=$(curl -s "https://gitee.com/api/v5/repos/$REPO_GITEE/releases/$id?access_token=$GT" \
        | python3 -c "import json,sys
try: print(' '.join(a['name'] for a in json.load(sys.stdin).get('assets',[])))
except Exception: print('')" 2>/dev/null || true)
  for f in "$APK" artifacts/SHA256SUMS.txt; do
    [ -f "$f" ] || continue
    local base; base=$(basename "$f")
    if echo " $have " | grep -qF " $base "; then
      ok "Gitee 已有 $base"
    else
      [ "$DRY_RUN" = "1" ] && { say "  [dry] 上传 $base"; continue; }
      curl -s -X POST "https://gitee.com/api/v5/repos/$REPO_GITEE/releases/$id/attach_files" \
        -F "access_token=$GT" -F "file=@$f" >/dev/null
      ok "Gitee 已传 $base"
    fi
  done
}

atomgit_release() {
  [ -z "$AT" ] && { warn "无 AtomGit token，跳过"; return 0; }
  local cur
  cur=$(curl -s -H "Authorization: Bearer $AT" \
        "https://atomgit.com/api/v5/repos/$REPO_ATOMGIT/releases?per_page=1" \
        | python3 -c "import json,sys
try: d=json.load(sys.stdin); print((d[0] if isinstance(d,list) and d else {}).get('tag_name',''))
except Exception: print('')" 2>/dev/null || true)
  if [ "$cur" = "$TAG" ]; then
    ok "AtomGit Release 已存在（$TAG），跳过"
  else
    [ "$DRY_RUN" = "1" ] && { say "  [dry] 创建 AtomGit Release $TAG"; return 0; }
    local payload
    payload=$(VER="$VER" TAG="$TAG" APK_NAME="$APK_NAME" SIZE="$SIZE" SHA="$SHA" python3 -c '
import json, os
tag = os.environ["TAG"]; apk = os.environ["APK_NAME"]
size = int(os.environ["SIZE"]); sha = os.environ["SHA"]
body = "\n".join([
    "## " + tag, "",
    "- 产物：`" + apk + "`，**{:,} 字节**".format(size),
    "- SHA-256：`" + sha + "`", "",
    "下载：https://gitee.com/westanke/dsh-Chat/releases/download/" + tag + "/" + apk,
])
print(json.dumps({"tag_name": tag, "name": os.environ["VER"],
                  "body": body, "target_commitish": "main"}))
')
    curl -s -X POST "https://atomgit.com/api/v5/repos/$REPO_ATOMGIT/releases" \
      -H "Authorization: Bearer $AT" -H 'Content-Type: application/json' -d "$payload" >/dev/null
    ok "AtomGit Release 已建（正文含 Gitee 下载链接）"
  fi
  warn "AtomGit 不支持附件上传（API 不存在），APK 以 Gitee 为准"
}

gitee_release
atomgit_release
say ""

say "4) 全渠道回读"
if [ "$DRY_RUN" = "1" ]; then
  say "  [dry] 跳过回读"
  exit 0
fi
rc=0
ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$APK_NAME")
code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 180 \
  "https://gitee.com/${REPO_GITEE}/releases/download/${TAG}/${ENC}")
[ "$code" = "200" ] && ok "Gitee: APK 可下载（200）" || { bad "Gitee: APK 返回 $code"; rc=1; }

for r in gitee atomgit; do
  if [ -n "$(git ls-remote --tags "$r" "refs/tags/$TAG" 2>/dev/null)" ]; then
    ok "$r: tag $TAG 已就位"
  else
    bad "$r: tag $TAG 缺失"; rc=1
  fi
done

# 下载回来的字节数必须与本地产物的 SHA 对得上（防「传了个旧包」）。
if [ "$rc" -eq 0 ]; then
  TMP_DL="artifacts/.verify-${TAG}.apk"
  curl -sL -o "$TMP_DL" --max-time 300 "https://gitee.com/${REPO_GITEE}/releases/download/${TAG}/${ENC}"
  DL_SHA=$(sha256sum "$TMP_DL" | cut -d' ' -f1)
  rm -f "$TMP_DL"
  if [ "$DL_SHA" = "$SHA" ]; then
    ok "下载回来的包 SHA-256 与本地一致（没有传错包）"
  else
    bad "下载回来的包 SHA 不一致：$DL_SHA vs $SHA"; rc=1
  fi
fi

say ""
if [ "$rc" -eq 0 ]; then
  ok "═══ 发版完成：双站 tag + 两站 Release + APK 全部就位 ═══"
  say "GitHub 从站由 mirror-sync workflow 自动对齐。"
else
  bad "═══ 有渠道未就位，见上方 ❌ ═══"
fi
exit "$rc"
