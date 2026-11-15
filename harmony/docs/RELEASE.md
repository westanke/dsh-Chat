# RELEASE —— 鸿蒙版构建与发版流程（骨架，AGC 材料齐后回填）

> 参照姊妹仓 dsh-companion-harmony `docs/RELEASE.md` 定稿的两段式流程，bundleName
> 换成 `com.dsh.dshchat`。推送/发布类动作**必须先获用户明确同意**（AGENTS.md §10）。

## 1. 本机构建（未签名，随时可做）

```sh
harmony/scripts/package.sh        # 双闸门：node 单测 + hvigorw assembleHap + 归集 dist/
```

产物：`harmony/dist/entry-default-unsigned.hap`（`WARN: No signingConfig` 属预期）。

## 2. 用户侧待补材料（仅真机验收与发版前需要）

| 材料 | 说明 |
|---|---|
| AGC 新建应用 | bundleName `com.dsh.dshchat`，与 AppScope/app.json5 一致 |
| 调试证书 + 调试 Profile | Profile 需登记现有 HarmonyOS 6.0 真机 UDID（companion 那台） |
| 发布证书 + 发布 Profile | 送审/上架用 |
| 密钥库 p12 | hap-sign-tool 用；口令**绝不**写进任何入库文件 |

材料落 `harmony/signing/`（已 .gitignore，**绝不入库**，泄露即证书作废）。

## 3. 签名（hap-sign-tool，hvigor 不参与）

骨架阶段未拿到 p12/cer/p7b，命令模板先占位（照姊妹仓 RELEASE.md §④ 回填精确参数）：

```sh
# 伪码占位 —— 材料齐后回填：
java -jar "$HARMONY_TOOLCHAIN/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar" \
  sign-app -keystore harmony/signing/<key>.p12 -keystorePwd '<口令>' \
  -appCertFile harmony/signing/<cert>.cer -profileFile harmony/signing/<profile>.p7b \
  -inFile dist/entry-default-unsigned.hap -outFile dist/<产物名>.hap
```

要点（姊妹仓实测）：
- Profile 里的 `bundle-name` 必须与 AppScope/app.json5 完全一致，否则签名失败。
- 文件名含空格/中文时命令行必须加引号。
- 真机安装走 `hdc install`（`$HDC` 在 toolchain-env.sh 里）。

## 4. 发版（阶段 5，全部需用户点头）

1. bump `AppScope/app.json5`（versionName+versionCode）与 `entry/oh-package.json5` version
   （test/cases/version-contract.test.ts 会机检两处一致）。
2. `harmony/scripts/package.sh` 全绿 → 产物 hap + SHA256SUMS.txt。
3. Gitee Release：传 hap + SHA256SUMS（正文口径与安卓版同款式：对外写
   「DSH Chat — HarmonyOS client for dsh-remote-bridge」，不写 DeepSeek 克隆）。
4. AtomGit Release 正文链 Gitee；GitHub Release 走既有镜像 + API 补建模式。
5. AGC 上架为可选独立步骤（姊妹仓有全套驳回→改名→过审经验可照搬）。
