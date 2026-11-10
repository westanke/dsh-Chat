#!/usr/bin/env python3
"""把发版产物的真实数字回填进 README（dsh-Chat 版）。

用法：
    scripts/backfill-release.py <version> <code> <bytes> <sha256> <apkName>

与 dsh-companion 同名脚本同源思路（回填单独成脚本，可单独跑、单独验证；
避免 release.sh 里 heredoc 嵌套打架）。每一处替换都带明确上下文锚点，
匹配不到就告警/中止 —— 绝不毁历史 APK 记录。

dsh-Chat 的回填锚点（README.md）：
1. 版本徽章  img.shields.io/badge/version-<ver>-087f8c
2.「当前状态」表：在表头后插入本次产物行（保留全部历史 APK 行；
   历次发版 fbe5eec 等都是手工在顶部插一行，此处复刻该惯例）
3.「当前状态」版本行：同步 pubspec 版本与 tag
4.「下载安装」小节：仅在该小节范围内更新产物行/校验行 tag/脚注版本
   —— 分段隔离，不再用会删光全局 | APK | 行的 re.subn 全局替换
"""
import re
import sys
import pathlib


def sync_app_version(ver: str, code: str) -> None:
    """把版本号写进设置页（必须在 flutter build 之前跑——版本是编译期常量，
    打包后才改就烧不进 APK 了；v1.0.3 装机显示旧版本就是这个顺序踩的）。"""
    settings = pathlib.Path("app/lib/ui/settings_page.dart")
    stext = settings.read_text(encoding="utf-8")
    sout, n = re.subn(
        r"(const String _appVersion = ')[\d.]+\+\d+(';)",
        rf"\g<1>{ver}+{code}\g<2>",
        stext,
    )
    if n != 1:
        print(f"  ❌ settings_page.dart _appVersion 锚点命中 {n} 处（期望 1）",
              file=sys.stderr)
        sys.exit(1)
    settings.write_text(sout, encoding="utf-8")
    print(f"  ✅ settings_page.dart _appVersion 已同步 {ver}+{code}")


def backfill(text: str, ver: str, code: str, size: int, sha: str, apk: str) -> str:
    size_fmt = f"{size:,}"
    gitee_dl = f"https://gitee.com/westanke/dsh-Chat/releases/download/v{ver}/{apk}"
    release_row = (
        f"| APK | [`{apk}`]({gitee_dl})<br>{size_fmt} 字节 · SHA-256 `{sha}` |\n"
    )

    def sub1(pattern, repl, s, *, label, flags=0):
        """命中恰好 1 处才替换，否则告警（锚点写错就宁可不动，绝不静默毁数据）。"""
        out, n = re.subn(pattern, repl, s, count=1, flags=flags)
        if n != 1:
            print(f"  ⚠️ 锚点未命中（期望 1 处，实际 {n}）：{label}", file=sys.stderr)
        return out, n

    out = text

    # 1) 版本徽章
    out, _ = sub1(
        r"(img\.shields\.io/badge/version-)[\d.]+(-087f8c)",
        rf"\g<1>{ver}\g<2>", out,
        label="版本徽章",
    )

    # 2)「当前状态」表：在表头后插入本次产物行，保留全部历史 APK 行。
    #    锚点用「当前状态」小节独有的表头；不能用全局 | APK | 正则（会删光历史）。
    out, n = sub1(
        r"(## 当前状态\n\n\| 平台 \| 状态 \|\n\|---\|---\|\n)",
        lambda m: m.group(1) + release_row, out,
        label="当前状态表表头（插入本次产物行）",
    )
    if n != 1:
        print("  ❌ 当前状态表锚点未命中，回填中止（README 保持不动）",
              file=sys.stderr)
        sys.exit(1)

    # 3)「当前状态」版本行：同步 pubspec 版本与 tag（兼容行内旧版本号措辞）。
    out, _ = sub1(
        r"(\| 版本 \| `app/pubspec\.yaml` 为 `)[\d.]+\+\d+(`；tag `)v[\d.]+(`，产物见下方「下载安装」 \|)",
        rf"\g<1>{ver}+{code}\g<2>v{ver}\g<3>", out,
        label="当前状态版本行",
    )

    # 4) 设置页版本号兜底校验：阶段 A 打包前已由 sync_app_version 写好，
    #    这里若仍不一致说明打包烧了旧值 —— 直接失败，不发坏包。
    settings = pathlib.Path("app/lib/ui/settings_page.dart")
    if f"const String _appVersion = '{ver}+{code}';" not in settings.read_text(
        encoding="utf-8"
    ):
        print("  ❌ settings_page.dart 版本与 pubspec 不一致（打包前没同步）",
              file=sys.stderr)
        sys.exit(1)

    # 5)「下载安装」小节：只在该小节范围内更新产物行/校验行 tag/脚注版本，
    #    分段隔离，绝不碰「当前状态」表的历史 APK 行。
    section_head = "## 下载安装"
    start = out.find(section_head)
    if start != -1:
        nxt = out.find("\n## ", start + len(section_head))
        end = nxt if nxt != -1 else len(out)
        seg = out[start:end]
        # 5a) 产物行（该段内唯一 | APK | 行）；lambda 避免 repl 被当反向引用解析
        seg, n1 = re.subn(
            r"^\| APK \|.*\n", lambda m: release_row, seg, count=1, flags=re.M
        )
        if n1 != 1:
            print(f"  ⚠️ 下载安装表 APK 行未定位（命中 {n1}）", file=sys.stderr)
        # 5b) 校验行的 tag
        seg, _ = re.subn(
            r"(tag `)v[\d.]+(` 内的 `artifacts/SHA256SUMS\.txt`)",
            rf"\g<1>v{ver}\g<2>", seg, count=1,
        )
        # 5c) 脚注当前版本
        seg, _ = re.subn(
            r"（当前 `[\d.]+\+\d+`",
            f"（当前 `{ver}+{code}`", seg, count=1,
        )
        out = out[:start] + seg + out[end:]
    else:
        # 首次发版：在「当前状态」小节后补一个下载安装小节
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
