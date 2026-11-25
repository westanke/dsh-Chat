#!/usr/bin/env python3
"""把发版产物的真实数字回填进 README.md / README.en.md（dsh-Chat 版）。

用法：
    scripts/backfill-release.py <version> <code> <bytes> <sha256> <apkName>
    scripts/backfill-release.py <version> <code> <bytes> <sha256> <apkName> \
                                <hapName> <hapBytes> <hapSha> [hapNote]

只改版本徽章、下载按钮/最新版、下载表 APK/HAP 行、当前版本行；
历史版本说明与「应用名」注保持不动。
"""
import re
import sys
import pathlib

def row_zh(kind, dl, size, sha, note=None):
    base = f"| [{kind}]({dl}) | {size:,} 字节 | `{sha}` |"
    if kind == "HAP" and note:
        base = f"| [{kind}]({dl}) | {size:,} 字节 | `{sha}`（{note}） |"
    return base

def row_en(kind, dl, size, sha, note=None):
    base = f"| [{kind}]({dl}) | {size:,} bytes | `{sha}` |"
    if kind == "HAP" and note:
        base = f"| [{kind}]({dl}) | {size:,} bytes | `{sha}` ({note}) |"
    return base

def backfill(text, ver, code, size, sha, apk, hap=None, hap_size=None, hap_sha=None,
             hap_note=None, lang="zh"):
    gitee = f"https://gitee.com/westanke/dsh-Chat/releases/download/v{ver}"
    apk_dl = f"{gitee}/{apk}"
    hap_dl = f"{gitee}/{hap}" if hap else None
    if lang == "zh":
        apk_row = row_zh("APK", apk_dl, size, sha)
        hap_row = row_zh("HAP", hap_dl, hap_size, hap_sha, hap_note) if hap else None
        section = "## 下载安装"
        latest_re = r"(最新版 \*\*)v[\d.]+(\*\*)"
        current_re = r"(当前版本：`app/pubspec\.yaml` 为 `)[\d.]+\+\d+(`，tag `)v[\d.]+(`)"
    else:
        apk_row = row_en("APK", apk_dl, size, sha)
        hap_row = row_en("HAP", hap_dl, hap_size, hap_sha, hap_note) if hap else None
        section = "## Download and install"
        latest_re = r"(Latest \*\*)v[\d.]+(\*\*)"
        current_re = r"(Current version: `app/pubspec\.yaml` is `)[\d.]+\+\d+(`, tag `)v[\d.]+(`)"

    out = text
    # 1) badge
    out = re.sub(r"(img\.shields\.io/badge/version-)[\d.]+(-087f8c)", rf"\g<1>{ver}\g<2>", out, count=1)
    # 2) top download button (first tag link only)
    out = re.sub(r"(releases/tag/)v[\d.]+", rf"\g<1>v{ver}", out, count=1)
    # 3) 最新版 / Latest
    out = re.sub(latest_re, rf"\g<1>v{ver}\g<2>", out, count=1)
    # 4) 当前版本行
    out = re.sub(current_re, rf"\g<1>{ver}+{code}\g<2>v{ver}\g<3>", out, count=1)
    # 5) 下载小节里的 APK/HAP 行（限定小节，避免碰历史表）
    start = out.find(section)
    if start != -1:
        nxt = out.find("\n## ", start + len(section))
        end = nxt if nxt != -1 else len(out)
        seg = out[start:end]
        seg, n_apk = re.subn(r"^\| \[APK\].*$", lambda m: apk_row, seg, count=1, flags=re.M)
        if hap_row:
            seg, n_hap = re.subn(r"^\| \[HAP\].*$", lambda m: hap_row, seg, count=1, flags=re.M)
            if n_hap != 1:
                seg, n_hap = re.subn(r"^(\| \[APK\].*)$", lambda m: m.group(1) + "\n" + hap_row, seg, count=1, flags=re.M)
        out = out[:start] + seg + out[end:]
    return out

def main():
    if len(sys.argv) not in (6, 9, 10):
        print(__doc__); sys.exit(1)
    ver, code, size, sha, apk = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
    hap = hap_size = hap_sha = hap_note = None
    if len(sys.argv) >= 9:
        hap, hap_size, hap_sha = sys.argv[6], int(sys.argv[7]), sys.argv[8]
    if len(sys.argv) == 10:
        hap_note = sys.argv[9]
    changed = False
    for path, lang in [("README.md", "zh"), ("README.en.md", "en")]:
        p = pathlib.Path(path)
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8")
        out = backfill(text, ver, code, size, sha, apk, hap, hap_size, hap_sha, hap_note, lang)
        if out != text:
            p.write_text(out, encoding="utf-8")
            print(f"  ✅ {path} 已回填 v{ver}+{code}")
            changed = True
        else:
            print(f"  ⚠️ {path} 无变化（可能已回填过）")
    if not changed:
        print("  ⚠️ 回填前后无变化（可能已回填过）")

if __name__ == "__main__":
    main()
