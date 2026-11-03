#!/usr/bin/env bash
# 文档契约机检 —— 模板仓 `pnpm docs:check` 在本仓的等价物。
#
# 宪法（AGENTS.md §8）要求：lib/ 下文件增删、改名、拆分，必须在**同一个提交**里
# 更新 docs/STRUCTURE.md。人肉记不住，所以做成门禁 —— 与 dsh-remote-bridge 的
# docs-contract 同一思路，只是 Flutter 仓没有 TS 运行时，用 bash + grep 实现，零依赖。
#
# 检查三条：
#   1) app/lib/ 下每个 .dart 文件都必须在 docs/STRUCTURE.md 里出现（按 lib/ 内相对路径匹配，
#      即表格里写 `ui/chat_page.dart` 这种形式）；
#   2) docs/STRUCTURE.md 里点名的 lib 文件必须真实存在（防改名后留死链）；
#   3) 不得残留旧仓库名（改名遗留）。检查时排除本脚本自身与 ref/ 历史快照。
#
# 用法：bash scripts/ci/docs-check.sh     退出码 0 = 通过
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1   # 定位到仓库根，CI 与本地行为一致

STRUCT="docs/STRUCTURE.md"
LIB="app/lib"
OLD_NAME="dsh-flutter-deepseek"        # 变量化：避免本文件自身被第 3 条检查命中
fail=0

say() { printf '%s\n' "$*"; }
bad() { printf '  ❌ %s\n' "$*"; fail=1; }

[ -f "$STRUCT" ] || { echo "::error::找不到 $STRUCT"; exit 1; }
[ -d "$LIB" ]    || { echo "::error::找不到 $LIB";  exit 1; }

# ── 1) lib/ 每个文件都被 STRUCTURE.md 收录 ──────────────────────────────
say "检查 $LIB/ 全部文件是否已登记进 $STRUCT …"
missing=0
while IFS= read -r f; do
  rel="${f#"$LIB"/}"                  # lib/ui/chat_page.dart → ui/chat_page.dart
  if ! grep -qF "\`$rel\`" "$STRUCT"; then
    bad "未登记：lib/$rel  →  请在 $STRUCT 的「## app/lib/」表里补一行"
    missing=$((missing + 1))
  fi
done < <(find "$LIB" -name '*.dart' -type f | sort)
[ "$missing" -eq 0 ] && say "  ✅ 全部已登记"

# ── 2) STRUCTURE.md 里点名的 dart 文件必须真实存在 ───────────────────────
# 表里同时登记 lib/（写 lib 内相对路径）、test/（写裸文件名）、tool/（写 tool/ 前缀）
# 三种写法，所以按「app/ 下同名文件是否存在」判定，避免误报。
say "检查 $STRUCT 中登记的文件是否仍存在 …"
ghost=0
while IFS= read -r rel; do
  base="$(basename "$rel")"
  if [ -f "$LIB/$rel" ] || [ -n "$(find app -name "$base" -type f -print -quit 2>/dev/null)" ]; then
    continue
  fi
  bad "死链：$rel  →  文件已不存在，请更新 $STRUCT"
  ghost=$((ghost + 1))
done < <(grep -oE '`[A-Za-z0-9_/]+\.dart`' "$STRUCT" | tr -d '`' | sort -u)
[ "$ghost" -eq 0 ] && say "  ✅ 无死链"

# ── 3) 旧仓库名残留 ────────────────────────────────────────────────────
# 两处合法出现，必须放过：
#   - ref/：从旧目录带过来的历史抓包与快照，里面的绝对路径是当时的事实记录，不回改；
#   - AGENTS.md §2.4：改名纪律本身就要写出旧名（「本仓原名 xxx，已改名」），
#     否则后人无从知道改过名。该行必须带 `改名纪律` 标记，脚本据此豁免。
say "检查改名前缀残留 …"
hits=$(grep -rIn "$OLD_NAME" \
        --include='*.md' --include='*.dart' --include='*.sh' \
        --include='*.yml' --include='*.yaml' --include='*.json' \
        --exclude-dir=.git --exclude-dir=build --exclude-dir=.dart_tool \
        --exclude-dir=ref --exclude="$(basename "$0")" . 2>/dev/null \
      | grep -v '改名纪律')   # 宪法 §2.4 的改名纪律行是有意提及旧名
if [ -n "$hits" ]; then
  bad "仍存在旧仓库名 $OLD_NAME（除 ref/ 与 §2.4 改名纪律行外不应有命中）"
  printf '%s\n' "$hits" | sed 's/^/      /'
else
  say "  ✅ 无残留"
fi

say ""
if [ "$fail" -eq 0 ]; then
  say "✅ 文档契约检查通过"
  exit 0
fi
say "❌ 文档契约检查失败：改了 lib/ 就请同提交更新 $STRUCT（宪法 §8）"
exit 1
