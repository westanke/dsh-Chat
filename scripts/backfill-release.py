#!/usr/bin/env python3
"""把发版产物的真实数字回填进 README（dsh-Chat 版）。

用法：
    scripts/backfill-release.py <version> <code> <bytes> <sha256> <apkName>

与 dsh-companion 同名脚本同源思路（回填单独成脚本，可单独跑、单独验证；
避免 release.sh 里 heredoc 嵌套打架）。每一处替换都带明确上下文锚点，
匹配不到就一个字节都不动 —— 绝不碰历史版本号。

dsh-Chat 的回填锚点（README.md）：
1. 版本徽章  img.shields.io/badge/version-1.0.0-087f8c
2. 「当前状态」表  | 版本 | `app/pubspec.yaml` 为 `1.0.0+1`；尚无 tag 与正式 release 产物 |
3. 新增/更新「下载安装」小节的产物行（APK 名 / 字节 / SHA-256 / tag 链接）
"""
import re
import sys
import pathlib


def backfill(text: str, ver: str, code: str, size: int, sha: str, apk: str) -> str:
    size_fmt = f"{size:,}"
    gitee_dl = f"https://gitee.com/westanke/dsh-Chat/releases/download/v{ver}/{apk}"
    reps = [
        # 1) 版本徽章
        (r"(img\.shields\.io/badge/version-)[\d.]+(-087f8c)", rf"\g<1>{ver}\g<2>"),
        # 2) 当前状态表的版本行（原文措辞固定，锚点唯一）
        (
            r"(\| 版本 \| `app/pubspec\.yaml` 为 `)[\d.]+\+\d+(`；尚无 tag 与正式 release 产物 \|)",
            rf"\g<1>{ver}+{code}\g<2>".replace(
                "；尚无 tag 与正式 release 产物", f"；tag `v{ver}`，产物见下方「下载安装」"
            ),
        ),
    ]
    out = text
    for pat, rep in reps:
        out, n = re.subn(pat, rep, out)
        if n != 1:
            print(f"  ⚠️ 锚点未命中（期望 1 处，实际 {n}）：{pat}", file=sys.stderr)

    release_row = (
        f"| APK | [`{apk}`]({gitee_dl})<br>{size_fmt} 字节 · SHA-256 `{sha}` |\n"
    )
    section_head = "## 下载安装"
    if section_head in out:
        # 更新已存在的产物表：替换 APK 行（锚点：行首 | APK |）
        out, n = re.subn(r"^\| APK \|.+\|\n$", release_row, out, flags=re.M)
        if n == 0:
            # 表还在但没 APK 行 → 插到表头分隔行后
            out, n = re.subn(
                r"(^\|---\|---\|\n)", rf"\1{release_row}", out, count=1, flags=re.M
            )
        if n != 1:
            print("  ⚠️ 下载安装表 APK 行未能定位", file=sys.stderr)
    else:
        # 首次发版：在「## 当前状态」小节后补一个下载安装小节
        anchor = "未验证的功能不会被写成「已完成」。真机截图是唯一验收证据。\n"
        section = (
            f"\n{section_head}\n\n"
            f"正式产物随 tag 发布（Gitee 主站）：\n\n"
            f"| 产物 | 说明 |\n|---|---|\n"
            f"{release_row}"
            f"| 校验 | `sha256sum -c` 前先比对上方 SHA-256；tag `v{ver}` 内的 "
            f"`artifacts/SHA256SUMS.txt` 为权威值 |\n\n"
            f"> 版本号以 [`app/pubspec.yaml`](app/pubspec.yaml) 的 `version` 为准"
            f"（当前 `{ver}+{code}`）。\n"
        )
        if anchor not in out:
            print("  ❌ 找不到「当前状态」小节锚点，回填中止", file=sys.stderr)
            sys.exit(1)
        out = out.replace(anchor, anchor + section, 1)
    return out


def main() -> None:
    if len(sys.argv) != 6:
        print(__doc__)
        sys.exit(1)
    ver, code, size, sha, apk = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
    readme = pathlib.Path("README.md")
    text = readme.read_text(encoding="utf-8")
    out = backfill(text, ver, code, size, sha, apk)
    if out == text:
        print("  ⚠️ 回填前后无变化（可能已回填过）")
    readme.write_text(out, encoding="utf-8")
    print(f"  ✅ README.md 已回填 v{ver}+{code} / {size:,} 字节 / {sha[:16]}…")


if __name__ == "__main__":
    main()
