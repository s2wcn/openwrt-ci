#!/bin/bash
# ==============================================================================
# libwrt.sh —— ZN_M2 (IPQ6000 / qualcommax-ipq60xx) OpenWrt 6.12 固件自定义脚本
#
# 设计原则：
#   1. 任何一步失败都必须让 CI 失败（set -euo pipefail），杜绝静默失败
#   2. 默认信任 Passwall 上游已联调验证的版本，不自动改版本
#      （避免 /releases/latest 跳过 pre-release 导致的降级，以及哈希污染）
#   3. 设 TRACK_LATEST=1 时才跟踪上游最新 tag，且版本号与 PKG_HASH 原子更新
#   4. 显式消除 Passwall 克隆包与 immortalwrt feed 的重复来源
#   5. 只有 .config 中真正启用的插件才克隆，保证"配置即真相"
#
# 环境变量：
#   TRACK_LATEST=1   跟踪上游最新 release（含 pre-release）并原子更新版本+哈希
#   PW_REF=<ref>     固定 passwall 仓库的分支/tag/commit，默认 main
#   GITHUB_TOKEN     建议注入，避免 GitHub API 匿名 60 次/小时限流
# ==============================================================================
set -euo pipefail

PW_REF="${PW_REF:-main}"
TRACK_LATEST="${TRACK_LATEST:-0}"

# 路径约定：
#   openwrt-passwall         根/luci-app-passwall/        （嵌套！）
#   openwrt-passwall2        根/luci-app-passwall2/       （嵌套！）
#   openwrt-passwall-packages 根/<component>/              （平铺）
# 因此读写 LuCI 端的 Makefile 时必须再进一层子目录。
PKG_LUCI_DIR="package/luci-app-passwall"               # 克隆目标
PKG_LUCI_MK="package/luci-app-passwall/luci-app-passwall/Makefile"
PKG_LUCI2_DIR="package/luci-app-passwall2"
PKG_LUCI2_MK="package/luci-app-passwall2/luci-app-passwall2/Makefile"
PKG_CORE="package/openwrt-passwall-packages"          # 平铺结构，直接用 <PKG_CORE>/<pkg>/Makefile
PKG_CORE_DEFAULT_BRANCH="xray-core"                    # 用于检测克隆是否完整

log()  { echo "::notice::$*"; }
warn() { echo "::warning::$*"; }
die()  { echo "::error::$*"; exit 1; }

# 必须在 OpenWrt 源码根目录运行
[ -f scripts/feeds ] || die "请在 OpenWrt 源码根目录运行本脚本（未找到 scripts/feeds）"
[ -f .config ]       || die "未找到 .config，请先拷贝编译配置"

# 每次重启都重新克隆（防止上一次半截残留）
[ -d "$PKG_LUCI_DIR" ]  && rm -rf "$PKG_LUCI_DIR"
[ -d "$PKG_LUCI2_DIR" ] && rm -rf "$PKG_LUCI2_DIR"
[ -d "$PKG_CORE" ]      && rm -rf "$PKG_CORE"

# ------------------------------------------------------------------------------
# 工具函数
# ------------------------------------------------------------------------------

# 判断 .config 中某包是否启用
config_enabled() { grep -qx "CONFIG_PACKAGE_$1=y" .config; }

# 读取 Makefile 中当前的 PKG_VERSION
pkg_version() {
  local mk="$1"
  awk -F':=' '/^PKG_VERSION[[:space:]]*:=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$mk"
}

# 写入 GitHub Actions 环境变量（本地运行时安全跳过）
emit_env() {
  [ -n "${GITHUB_ENV:-}" ] && echo "$1=$2" >> "$GITHUB_ENV"
  return 0
}

# 取最新 release tag（含 pre-release，跳过 draft）。失败返回 1。
latest_release_tag() {
  local repo="$1" out
  local -a hdrs=( -H "Accept: application/vnd.github+json" )
  [ -n "${GITHUB_TOKEN:-}" ] && hdrs+=( -H "Authorization: Bearer ${GITHUB_TOKEN}" )

  # /releases?per_page=N 按创建时间倒序返回，且包含 pre-release
  # （/releases/latest 会跳过 pre-release，Xray-core 因此会被降级到 26.3.27）
  # 再用 test() 只保留"纯数字点分"版本号，排除 1.15.0-alpha.2 这类 alpha/beta/rc
  out=$(curl -fsSL --retry 3 --retry-delay 3 --max-time 30 "${hdrs[@]}" \
        "https://api.github.com/repos/${repo}/releases?per_page=50" \
      | jq -r '[ .[] | select(.draft | not) | .tag_name
                 | select(test("^v?[0-9]+(\\.[0-9]+){1,3}$")) ] | first // empty') || return 1

  out="${out#v}"
  # 二次校验：拦截 "null" / "API rate limit exceeded" 等噪声
  [[ "$out" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || return 1
  printf '%s' "$out"
}

# 计算 codeload 源码包 sha256。失败返回 1。
source_tarball_hash() {
  local repo="$1" ver="$2" tmp
  tmp="$(mktemp)"
  # -f：HTTP 4xx/5xx 直接非零退出，杜绝把 404 错误页（14 字节）当成源码包
  if ! curl -fsSL --retry 3 --retry-delay 3 --max-time 300 \
        -o "$tmp" "https://codeload.github.com/${repo}/tar.gz/v${ver}"; then
    rm -f "$tmp"; return 1
  fi
  # 二次校验：源码包体积不可能小于 10KB
  if [ "$(wc -c < "$tmp")" -lt 10240 ]; then
    rm -f "$tmp"; return 1
  fi
  sha256sum "$tmp" | awk '{print $1}'
  rm -f "$tmp"
}

# 原子更新包的版本与哈希。任何异常都保持原版本，绝不写 PKG_HASH:=skip。
update_pkg() {
  local pkg="$1" repo="$2" ver="$3" mk cur hash
  mk="${PKG_CORE}/${pkg}/Makefile"
  [ -f "$mk" ] || { warn "未找到 ${mk}，跳过 ${pkg}"; return 0; }

  cur="$(pkg_version "$mk")"
  [ "$cur" = "$ver" ] && { log "${pkg}: 已是 ${ver}"; return 0; }

  if ! hash="$(source_tarball_hash "$repo" "$ver")"; then
    warn "${pkg}: 无法获取 v${ver} 源码包，保持原版本 ${cur}"
    return 0
  fi

  # 版本号与哈希必须同时替换
  sed -i -e "s/^PKG_VERSION[[:space:]]*:=.*/PKG_VERSION:=${ver}/" \
         -e "s/^PKG_HASH[[:space:]]*:=.*/PKG_HASH:=${hash}/" "$mk"

  grep -qx "PKG_VERSION:=${ver}" "$mk" || die "${pkg}: 版本写入失败"
  log "${pkg}: ${cur} -> ${ver}"
}

# 稀疏克隆（补齐原脚本中缺失的定义）
git_sparse_clone() {
  local branch="$1" url="$2" dir="$3"; shift 3
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  git -C "$dir" config core.sparseCheckout true
  printf '%s\n' "$@" > "$dir/.git/info/sparse-checkout"
  git -C "$dir" fetch -q --depth 1 origin "$branch"
  git -C "$dir" checkout -q "$branch"
}

# ------------------------------------------------------------------------------
# 1. 消除重复来源：Passwall 克隆包会与 immortalwrt feed 中的同名包冲突
#    （immortalwrt@openwrt-25.12 的 sing-box 仍是 1.12.25，落后两个小版本）
# ------------------------------------------------------------------------------
log "清理 feeds 中与 Passwall 重复的包来源..."
rm -rf feeds/packages/net/{xray-core,sing-box,xray-plugin,chinadns-ng,dns2socks,geoview,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-geodata,v2ray-plugin,hysteria}
rm -rf feeds/luci/applications/luci-app-passwall

# 保留原有的清理项（修正 appations -> applications 拼写错误）
rm -rf feeds/packages/net/{mosdns,msd_lite,smartdns}
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/{luci-app-mosdns,luci-app-netdata}

# ------------------------------------------------------------------------------
# 2. 克隆 Passwall（主仓库 + 依赖组件集合）
# ------------------------------------------------------------------------------
log "克隆 Passwall 组件（ref=${PW_REF}）..."
git clone --depth 1 -b "$PW_REF" https://github.com/Openwrt-Passwall/openwrt-passwall-packages "$PKG_CORE" \
  || die "克隆 $PKG_CORE 失败"
[ -d "${PKG_CORE}/${PKG_CORE_DEFAULT_BRANCH}" ] \
  || die "$PKG_CORE/${PKG_CORE_DEFAULT_BRANCH} 不存在，克隆可能不完整（请检查分支 ${PW_REF} 是否存在）"

git clone --depth 1 -b "$PW_REF" https://github.com/Openwrt-Passwall/openwrt-passwall "$PKG_LUCI_DIR" \
  || die "克隆 $PKG_LUCI_DIR 失败"
[ -f "$PKG_LUCI_MK" ] \
  || die "未找到 $PKG_LUCI_MK（上游 openwrt-passwall 的目录结构可能又改了，请到 https://github.com/Openwrt-Passwall/openwrt-passwall 核对）"

# 只有配置里启用了 passwall2 才克隆
if config_enabled luci-app-passwall2; then
  git clone --depth 1 -b "$PW_REF" https://github.com/Openwrt-Passwall/openwrt-passwall2 "$PKG_LUCI2_DIR" \
    || die "克隆 $PKG_LUCI2_DIR 失败"
  [ -f "$PKG_LUCI2_MK" ] \
    || die "未找到 $PKG_LUCI2_MK（上游 openwrt-passwall2 的目录结构可能又改了）"
fi

# ------------------------------------------------------------------------------
# 3. 可选插件：仅当 .config 中真正启用时才克隆
# ------------------------------------------------------------------------------
if config_enabled luci-app-openclash; then
  log "克隆 OpenClash..."
  git_sparse_clone main https://github.com/vernesong/OpenClash luci-app-openclash
fi

if config_enabled luci-app-smartdns || config_enabled smartdns; then
  log "克隆 SmartDNS..."
  git clone --depth 1 -b lede https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns
  git clone --depth 1 https://github.com/pymumu/openwrt-smartdns package/smartdns
fi

# ------------------------------------------------------------------------------
# 4. 版本处理
#    默认：信任上游，只读不写（推荐）
#    TRACK_LATEST=1：跟踪最新 release，版本号与哈希原子更新
# ------------------------------------------------------------------------------
if [ "$TRACK_LATEST" = "1" ]; then
  log "TRACK_LATEST=1，跟踪上游最新版本..."
  for spec in "xray-core:XTLS/Xray-core" "sing-box:SagerNet/sing-box"; do
    pkg="${spec%%:*}"; repo="${spec#*:}"
    if ver="$(latest_release_tag "$repo")"; then
      update_pkg "$pkg" "$repo" "$ver"
    else
      warn "${pkg}: 获取最新版本号失败，保持 Passwall 上游版本"
    fi
  done
else
  log "使用 Passwall 上游已验证版本（不自动改写）。如需跟踪最新请设 TRACK_LATEST=1"
fi

# ------------------------------------------------------------------------------
# 5. 版本一致性校验 + 输出（供 Release 说明使用，避免手写漂移）
# ------------------------------------------------------------------------------
XRAY_VER="$(pkg_version "${PKG_CORE}/xray-core/Makefile")"
SB_VER="$(pkg_version "${PKG_CORE}/sing-box/Makefile")"
PW_VER="$(pkg_version "$PKG_LUCI_MK")"

[ -n "$XRAY_VER" ] || die "未能读取 xray-core 版本"
[ -n "$SB_VER" ]   || die "未能读取 sing-box 版本"
[ -n "$PW_VER" ]   || die "未能读取 luci-app-passwall 版本（Makefile: $PKG_LUCI_MK）"

# 配置与脚本一致性校验：声明要用的必须真的启用
for p in luci-app-passwall; do
  config_enabled "$p" || die "配置未启用 ${p}，但本脚本假定其已启用。请检查 .config 或调整脚本"
done

emit_env "XRAY_VERSION"    "$XRAY_VER"
emit_env "SINGBOX_VERSION" "$SB_VER"
emit_env "PASSWALL_VERSION" "$PW_VER"

log "Passwall=${PW_VER}  Xray-core=${XRAY_VER}  Sing-box=${SB_VER}"
log "libwrt.sh 执行完成"
