# 由 install-harmony-toolchain.sh 生成的鸿蒙构建环境（本仓副本，可编辑）。
#
# 用法：source harmony/scripts/toolchain-env.sh
# ROOT 解析顺序：DSH_HARMONY_TOOLCHAIN_ROOT 环境变量 → dsh-companion-harmony 旁边
# 的共享工具链（TRae_work/_toolchain，与本机现存环境一致）。
# 工具链丢了就跑 harmony/scripts/install-harmony-toolchain.sh（国内源，分钟级）。
TOOLCHAIN_ROOT="${DSH_HARMONY_TOOLCHAIN_ROOT:-/media/wangke/OFFICE/TRae_work/_toolchain}"
if [ ! -d "$TOOLCHAIN_ROOT/command-line-tools" ]; then
  echo "toolchain-env.sh: 找不到鸿蒙工具链 $TOOLCHAIN_ROOT（先跑 scripts/install-harmony-toolchain.sh）" >&2
  return 1 2>/dev/null || exit 1
fi
export JAVA_HOME="$TOOLCHAIN_ROOT/jdk/current"
export NODE_HOME="$TOOLCHAIN_ROOT/node/current"
export HARMONY_TOOLCHAIN="$TOOLCHAIN_ROOT/command-line-tools"
export DEVECO_SDK_HOME="$HARMONY_TOOLCHAIN/sdk"
export HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
export PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$HARMONY_TOOLCHAIN/bin:$DEVECO_SDK_HOME/default/openharmony/toolchains:$PATH"
# 国内源
export npm_config_registry="https://registry.npmmirror.com"
export OHPM_REGISTRY="https://ohpm.openharmony.cn/ohpm/"
