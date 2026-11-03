#!/usr/bin/env bash
# 整理三个推送远端的命名与地址（幂等，可反复跑）。
#
# 目标约定：
#   origin   -> GitHub     git@github.com:westanke/dsh-Chat.git           （从站）
#   gitee    -> Gitee      git@gitee.com:westanke/dsh-Chat.git            （主）
#   atomgit  -> AtomGit    git@atomgit.com:westanke163/dsh-Chat.git       （备）
#
# 渠道拓扑（与 dsh-remote-bridge / dsh-companion 一致）：Gitee 为主、AtomGit 为备，
# GitHub 为从站 —— GitHub 端不手工推送，由 .github/workflows/mirror-sync.yml
# 定时从 Gitee 自动同步。
#
# 为什么这里直接写 SSH 地址，而模板仓 dsh-remote-bridge 写的是 HTTPS：
# 本机的全局 url.insteadOf 只重写了 GitHub 一条
# （`url.git@github.com:.insteadOf https://github.com/`），Gitee/AtomGit 的 HTTPS
# 地址若写进 remote 就必须依赖凭证助手里的 PAT —— 而本机 tokens.conf 是空的，
# 全靠 ~/.ssh/id_ed25519_{github,gitee,atomgit} 三把密钥。姊妹仓的三远端也已经全部
# 从 HTTPS 改成 SSH。所以这一版直接写 SSH，少一层隐式转换。
#
# 用法：bash scripts/setup-remotes.sh
set -uo pipefail

GITHUB_URL="git@github.com:westanke/dsh-Chat.git"
GITEE_URL="git@gitee.com:westanke/dsh-Chat.git"
ATOMGIT_URL="git@atomgit.com:westanke163/dsh-Chat.git"

say() { printf '%s\n' "$*"; }
ok()  { printf '  ✅ %s\n' "$*"; }
bad() { printf '  ❌ %s\n' "$*"; }

set_remote() {
  local name="$1" url="$2"
  if git remote get-url "$name" >/dev/null 2>&1; then
    local cur; cur="$(git remote get-url "$name")"
    if [ "$cur" = "$url" ]; then
      say "  $name 已就位：$url"
    else
      git remote set-url "$name" "$url" && ok "$name 改为：$url（原：$cur）"
    fi
  else
    git remote add "$name" "$url" && ok "新增 $name：$url"
  fi
}

say "整理三远端命名…"
say ""
set_remote origin  "$GITHUB_URL"
set_remote gitee   "$GITEE_URL"
set_remote atomgit "$ATOMGIT_URL"

say ""
say "当前远端："
git remote -v | awk '!seen[$1]++ {print "  " $1 "\t" $2}'
say ""
ok "三远端命名已统一（origin=GitHub 从站 / gitee=Gitee 主站 / atomgit=AtomGit 备站）"
