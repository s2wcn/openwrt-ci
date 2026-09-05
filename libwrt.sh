#!/bin/bash

# 修改默认IP
# sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
# sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# -------------------------------------------------------------------
# 1. 移除要替换的包及官方 Feeds 中的旧版 Xray / Sing-box / Passwall 源码
# -------------------------------------------------------------------
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/msd_lite
rm -rf feeds/packages/net/smartdns
rm -rf feeds/packages/net/xray-core
rm -rf feeds/packages/net/sing-box
rm -rf feeds/packages/net/v2ray-geodata
rm -rf feeds/packages/net/v2ray-core
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata
rm -rf feeds/luci/applications/luci-app-passwall

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# 添加额外插件
# git clone --depth=1 https://github.com/kongfl888/luci-app-adguardhome package/luci-app-adguardhome
# git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata
# git_sparse_clone master https://github.com/syb999/openwrt-19.07.1 package/network/services/msd_lite

# -------------------------------------------------------------------
# 2. 科学上网插件及 Upstream 最新核心组件库
# -------------------------------------------------------------------
git clone --depth=1 -b main https://github.com/fw876/helloworld package/luci-app-ssr-plus
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages package/openwrt-passwall-packages
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall package/luci-app-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2
git_sparse_clone master https://github.com/vernesong/OpenClash luci-app-openclash

# Themes
git clone --depth=1 -b 18.06 https://github.com/kiddin9/luci-theme-edge package/luci-theme-edge
git clone --depth=1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/xiaoqingfengATGH/luci-theme-infinityfreedom package/luci-theme-infinityfreedom
git_sparse_clone main https://github.com/haiibo/packages luci-theme-opentomcat

# 更改 Argon 主题背景
cp -f $GITHUB_WORKSPACE/images/bg1.jpg package/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg

# SmartDNS
git clone --depth=1 -b lede https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns
git clone --depth=1 https://github.com/pymumu/openwrt-smartdns package/smartdns

# msd_lite
git clone --depth=1 https://github.com/ximiTech/luci-app-msd_lite package/luci-app-msd_lite
git clone --depth=1 https://github.com/ximiTech/msd_lite package/msd_lite

# MosDNS
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns

# Alist
git clone --depth=1 https://github.com/sbwml/luci-app-alist package/luci-app-alist

# iStore
git_sparse_clone main https://github.com/linkease/istore-ui app-store-ui
git_sparse_clone main https://github.com/linkease/istore luci

# 在线用户
git_sparse_clone main https://github.com/haiibo/packages luci-app-onliner
sed -i '$i uci set nlbwmon.@nlbwmon[0].refresh_interval=2s' package/lean/default-settings/files/zzz-default-settings
sed -i '$i uci commit nlbwmon' package/lean/default-settings/files/zzz-default-settings
chmod 755 package/luci-app-onliner/root/usr/share/onliner/setnlbw.sh

# 修复 hostapd 报错
# cp -f $GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch

# 修复 armv8 设备 xfsprogs 报错
# sed -i 's/TARGET_CFLAGS.*/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/g' feeds/packages/utils/xfsprogs/Makefile

# 修改 Makefile
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -I {} sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -I {} sed -i 's/..\/..\/lang\/golang\/golang-package.mk/$(TOPDIR)\/feeds\/packages\/lang\/golang\/golang-package.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -I {} sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -I {} sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {}

# -------------------------------------------------------------------
# 3. 自动匹配 GitHub 最新 Release 版本号（含连接超时保护）
# -------------------------------------------------------------------
echo "开始更新 Xray-core..."
XRAY_VER=$(curl -sL --connect-timeout 5 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/v//g')
XRAY_MK=$(find package feeds -maxdepth 4 -type f -wholename "*/xray-core/Makefile" | head -n 1)
if [ -n "$XRAY_MK" ] && [ -n "$XRAY_VER" ]; then
    echo "找到 Xray-core Makefile: $XRAY_MK，更新至 $XRAY_VER"
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$XRAY_VER/g" "$XRAY_MK"
    sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/g" "$XRAY_MK"
fi

echo "开始更新 Sing-box..."
SB_VER=$(curl -sL --connect-timeout 5 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/v//g')
SB_MK=$(find package feeds -maxdepth 4 -type f -wholename "*/sing-box/Makefile" | head -n 1)
if [ -n "$SB_MK" ] && [ -n "$SB_VER" ]; then
    echo "找到 Sing-box Makefile: $SB_MK，更新至 $SB_VER"
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$SB_VER/g" "$SB_MK"
    sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/g" "$SB_MK"
fi

# -------------------------------------------------------------------
# 4. 安装包依赖
# -------------------------------------------------------------------
./scripts/feeds install -a
