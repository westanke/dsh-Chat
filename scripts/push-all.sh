#!/usr/bin/env bash
# 一次推送到主、备两个远端：Gitee（主）+ AtomGit（备）。
#
# 渠道拓扑（与 dsh-remote-bridge / dsh-companion 一致）：
#   gitee    -> Gitee    gitee.com/westanke/dsh-Chat.git          （主站）
#   atomgit  -> AtomGit  atomgit.com/westanke163/dsh-Chat.git     （备站）
#   origin   -> GitHub   github.com/westanke/dsh-Chat.git         （从站，自动同步）
#
# 为什么 GitHub 不手工推：本机到 github.com:443 长期被阻断（HTTP 层挂起超时），
# 而 GitHub 端由 .github/workflows/mirror-sync.yml 定时 + 手动从 Gitee 自动同步。
# 确有需要手工补推 GitHub 时加 INCLUDE_GITHUB=1（链路不通会独立失败，不影响主备）。
#
# 为什么分开推而不是给一个 remote 塞多个 pushurl：分开推各自独立报告，
# 一个站挂了不拖死另一个。
#
# 用法：
#   bash scripts/push-all.sh                     # 推当前分支（默认 main）到 Gitee + AtomGit
#   PUSH_TAGS=1 bash scripts/push-all.sh          # 分支 + 推「指向 HEAD 的 tag」（逐个）
#   PUSH_TAGS=1 PUSH_ALL_TAGS=1 bash scripts/push-all.sh   # 分支 + 推全部 tag（逐个）
#   BRANCH=dev bash scripts/push-all.sh           # 换分支
#   FORCE=1 bash scripts/push-all.sh              # 历史分叉时 --force-with-lease（默认绝不强推）
#   INCLUDE_GITHUB=1 bash scripts/push-all.sh     # 同时尽力推 GitHub
#
# 首次配置远端：bash scripts/setup-remotes.sh
set -uo pipefail

BRANCH="${BRANCH:-main}"
PUSH_TAGS="${PUSH_TAGS:-0}"
FORCE="${FORCE:-0}"
INCLUDE_GITHUB="${INCLUDE_GITHUB:-0}"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✅ %s\n' "$*"; }
bad()  { printf '  ❌ %s\n' "$*"; }

# ── 远端自检 ────────────────────────────────────────────────────────────
missing=0
for r in gitee atomgit; do
  if ! git remote get-url "$r" >/dev/null 2>&1; then
    bad "尚未配置 $r remote"
    missing=1
  fi
done
if [ "$INCLUDE_GITHUB" = "1" ] && ! git remote get-url origin >/dev/null 2>&1; then
  bad "INCLUDE_GITHUB=1 但未配置 origin remote"
  missing=1
fi
if [ "$missing" -ne 0 ]; then
  say ""
  say "先配远端：bash scripts/setup-remotes.sh"
  exit 1
fi

# 空仓保护：全新仓库还没有任何提交时，直接推 main 会报
# "src refspec main does not match any" —— 这个报错看不懂，不如提前说清楚。
if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  bad "当前仓库还没有任何提交，先提交再推：git add -A && git commit -m \"…\""
  exit 1
fi

# ── 推送清单（顺序 = 主 → 备 → [从]）────────────────────────────────────
PAIRS=("gitee:Gitee" "atomgit:AtomGit")
[ "$INCLUDE_GITHUB" = "1" ] && PAIRS+=("origin:GitHub")

force_args=()
[ "$FORCE" = "1" ] && force_args=(--force-with-lease)

fail=0

# ── 1) 先推分支（关键路径）──────────────────────────────────────────
# 分支与 tag 必须**先后独立**执行，不能 if/else 互斥 —— 否则带 PUSH_TAGS=1
# 就永远不推分支，远端看起来「只推了一半」，发版时最危险。
say "推送分支 $BRANCH（${#PAIRS[@]} 个远端，各自独立）…"
[ "$FORCE" = "1" ] && say "（FORCE=1：走 --force-with-lease 强制覆盖）"
say ""
for pair in "${PAIRS[@]}"; do
  r="${pair%%:*}"; label="${pair##*:}"
  say "→ $label ($r)"
  # 首次推送加 -u 建立 upstream 跟踪，之后的 `git status` 才能显示领先/落后。
  if git rev-parse --verify -q "refs/remotes/$r/$BRANCH" >/dev/null 2>&1; then
    push_args=()
  else
    push_args=(-u)
  fi
  if git push "${push_args[@]}" "${force_args[@]}" "$r" "$BRANCH"; then
    ok "$label 分支推送成功"
  else
    bad "$label 分支推送失败"
    if git rev-parse --verify -q "$r/$BRANCH" >/dev/null 2>&1 \
       && ! git merge-base --is-ancestor "$r/$BRANCH" HEAD 2>/dev/null; then
      say "    ⚠️ 检测到历史分叉：$r/$BRANCH 不是本地 $BRANCH 的祖先"
      say "    确认内容一致后可用 FORCE=1 强制覆盖：FORCE=1 bash scripts/push-all.sh"
    fi
    fail=1
  fi
  say ""
done

# ── 2) 再推 tag（逐个推，失败不阻塞分支）────────────────────────────
# 为什么不用 `git push --tags`：只要远端存在**任意一个**本地同名的旧 tag，
# 整条 --tags 推送就会被拒（"该标签在远程已经存在"），新 tag 也一起推不上去。
# 逐个推 + 逐个判断，才能让「新发的这个 tag」稳稳落地。
if [ "$PUSH_TAGS" = "1" ]; then
  # 默认只推**指向当前 HEAD** 的 tag（那才是这一版）；PUSH_ALL_TAGS=1 才推全部。
  if [ "${PUSH_ALL_TAGS:-0}" = "1" ]; then
    tags=$(git tag --list)
    say "推送全部 tag（逐个，${#PAIRS[@]} 个远端）…"
  else
    tags=$(git tag --points-at HEAD)
    say "推送指向 HEAD 的 tag（逐个，${#PAIRS[@]} 个远端）…"
  fi
  if [ -z "$tags" ]; then
    say "（没有要推的 tag —— 指向 HEAD 的 tag 为空；要推全部请用 PUSH_ALL_TAGS=1）"
  fi
  for t in $tags; do
    for pair in "${PAIRS[@]}"; do
      r="${pair%%:*}"; label="${pair##*:}"
      # 远端已有同名 tag 时**不算失败**：重跑脚本、或补推分支后重跑，都会撞上它。
      if [ -n "$(git ls-remote --tags "$r" "refs/tags/$t" 2>/dev/null)" ]; then
        say "  $label: $t 已存在，跳过"
        continue
      fi
      if git push "${force_args[@]}" "$r" "refs/tags/$t" >/dev/null 2>&1; then
        ok "$label: $t 推送成功"
      else
        bad "$label: $t 推送失败"
        fail=1
      fi
    done
  done
  say ""
fi

if [ "$fail" -eq 0 ]; then
  if [ "$INCLUDE_GITHUB" = "1" ]; then
    ok "三端都已更新"
  else
    ok "主备两站已更新（GitHub 从站等自动同步）"
  fi
else
  bad "至少有一个远端推送失败，见上方明细"
fi
exit "$fail"
