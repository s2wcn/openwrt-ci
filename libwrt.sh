#!/bin/bash

# 修改默认IP
# sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
# sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

echo "========================================"
echo "开始执行自定义配置脚本 (libwrt.sh)"
echo "========================================"

# 移除要替换的包
echo "第1步：清理冗余包..."
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/msd_lite
rm -rf feeds/packages/net/smartdns
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata

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

# 科学上网插件
echo "第2步：添加科学上网插件 (Passwall & 代理工具)..."
git clone --depth=1 -b main https://github.com/fw876/helloworld package/luci-app-ssr-plus
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall-packages
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
git clone --depth=1 -b main https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2
git_sparse_clone master https://github.com/vernesong/OpenClash luci-app-openclash

# Themes
echo "第3步：添加主题和UI..."
git clone --depth=1 -b 18.06 https://github.com/kiddin9/luci-theme-edge package/luci-theme-edge
git clone --depth=1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/xiaoqingfengATGH/luci-theme-infinityfreedom package/luci-theme-infinityfreedom
git_sparse_clone main https://github.com/haiibo/packages luci-theme-opentomcat

# 更改 Argon 主题背景
cp -f $GITHUB_WORKSPACE/images/bg1.jpg package/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg

# SmartDNS
echo "第4步：添加SmartDNS、MosDNS等工具..."
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
echo "第5步：配置在线用户监控..."
git_sparse_clone main https://github.com/haiibo/packages luci-app-onliner
sed -i '$i uci set nlbwmon.@nlbwmon[0].refresh_interval=2s' package/lean/default-settings/files/zzz-default-settings
sed -i '$i uci commit nlbwmon' package/lean/default-settings/files/zzz-default-settings
chmod 755 package/luci-app-onliner/root/usr/share/onliner/setnlbw.sh

# 修复 hostapd 报错
# cp -f $GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch

# 修复 armv8 设备 xfsprogs 报错
# sed -i 's/TARGET_CFLAGS.*/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/g' feeds/packages/utils/xfsprogs/Makefile

# 修改 Makefile (已将过时的 xargs -i 替换为标准的 xargs -I {})
echo "第6步：修复Makefile兼容性问题..."
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -I {} sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -I {} sed -i 's/..\/..\/lang\/golang\/golang-package.mk/$(TOPDIR)\/feeds\/packages\/lang\/golang\/golang-package.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -I {} sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -I {} sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {}

# 取消主题默认设置
# find package/luci-theme-*/* -type f -name '*luci-theme-*' -print -exec sed -i '/set luci.main.mediaurlbase/d' {} \;

# 调整 Docker 到 服务 菜单
# sed -i 's/"admin"/"admin", "services"/g' feeds/luci/applications/luci-app-dockerman/luasrc/controller/*.lua
# sed -i 's/"admin"/"admin", "services"/g; s/admin\//admin\/services\//g' feeds/luci/applications/luci-app-dockerman/luasrc/model/cbi/dockerman/*.lua
# sed -i 's/admin\//admin\/services\//g' feeds/luci/applications/luci-app-dockerman/luasrc/view/dockerman/*.htm
# sed -i 's|admin\\|admin\\/services\\|g' feeds/luci/applications/luci-app-dockerman/luasrc/view/dockerman/container.htm

# 调整 ZeroTier 到 服务 菜单
# sed -i 's/vpn/services/g; s/VPN/Services/g' feeds/luci/applications/luci-app-zerotier/luasrc/controller/zerotier.lua
# sed -i 's/vpn/services/g' feeds/luci/applications/luci-app-zerotier/luasrc/view/zerotier/zerotier_status.htm

# 取消对 samba4 的菜单调整
# sed -i '/samba4/s/^/#/' package/lean/default-settings/files/zzz-default-settings

# ==========================================
# 第7步：自动更新最新版本组件
# ==========================================
echo ""
echo "========================================"
echo "第7步：自动获取GitHub最新版本组件"
echo "========================================"

# ==========================================
# 自动更新 Xray-core 为 GitHub 最新版本
# ==========================================
echo "🔄 正在检查并更新 Xray-core..."
XRAY_VER=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*' | head -1 | cut -d'"' -f4 | sed 's/v//g')
XRAY_MK=$(find package feeds -maxdepth 4 -type f -wholename "*/xray-core/Makefile" 2>/dev/null | head -n 1)

if [ -n "$XRAY_MK" ] && [ -n "$XRAY_VER" ]; then
    echo "✅ 找到 Xray-core Makefile: $XRAY_MK"
    echo "📌 准备更新至版本: $XRAY_VER"
    # 替换版本号
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$XRAY_VER/g" "$XRAY_MK"
    # 将哈希校验设置为 skip
    sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/g" "$XRAY_MK"
    echo "✅ Xray-core 已更新至 $XRAY_VER"
else
    echo "⚠️  警告：未找到 Xray-core 的 Makefile 或无法获取最新版本"
    if [ -z "$XRAY_VER" ]; then
        echo "  - 可能原因：网络连接问题或 GitHub API 限制"
    fi
    if [ -z "$XRAY_MK" ]; then
        echo "  - 可能原因：Xray-core 包还未被 feeds install"
    fi
fi

# ==========================================
# 自动更新 Sing-box 为 GitHub 最新版本
# ==========================================
echo ""
echo "🔄 正在检查并更新 Sing-box..."
SB_VER=$(curl -sL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*' | head -1 | cut -d'"' -f4 | sed 's/v//g')
SB_MK=$(find package feeds -maxdepth 4 -type f -wholename "*/sing-box/Makefile" 2>/dev/null | head -n 1)

if [ -n "$SB_MK" ] && [ -n "$SB_VER" ]; then
    echo "✅ 找到 Sing-box Makefile: $SB_MK"
    echo "📌 准备更新至版本: $SB_VER"
    # 替换版本号
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$SB_VER/g" "$SB_MK"
    # 跳过哈希校验
    sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/g" "$SB_MK"
    echo "✅ Sing-box 已更新至 $SB_VER"
else
    echo "⚠️  警告：未找到 Sing-box 的 Makefile 或无法获取最新版本"
    if [ -z "$SB_VER" ]; then
        echo "  - 可能原因：网络连接问题或 GitHub API 限制"
    fi
    if [ -z "$SB_MK" ]; then
        echo "  - 可能原因：Sing-box 包还未被 feeds install"
    fi
fi

# ==========================================
# 自动更新 Tailscale 为 GitHub 最新版本
# ==========================================
echo ""
echo "🔄 正在检查并更新 Tailscale..."
TS_VER=$(curl -sL "https://api.github.com/repos/tailscale/tailscale/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*' | head -1 | cut -d'"' -f4 | sed 's/v//g')
TS_MK=$(find package feeds -maxdepth 4 -type f -wholename "*/tailscale/Makefile" 2>/dev/null | head -n 1)

if [ -n "$TS_MK" ] && [ -n "$TS_VER" ]; then
    echo "✅ 找到 Tailscale Makefile: $TS_MK"
    echo "📌 准备更新至版本: $TS_VER"
    # 替换版本号
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$TS_VER/g" "$TS_MK"
    # 跳过哈希校验
    sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/g" "$TS_MK"
    echo "✅ Tailscale 已更新至 $TS_VER"
else
    echo "⚠️  警告：未找到 Tailscale 的 Makefile 或无法获取最新版本"
    if [ -z "$TS_VER" ]; then
        echo "  - 可能原因：网络连接问题或 GitHub API 限制"
    fi
    if [ -z "$TS_MK" ]; then
        echo "  - 可能原因：Tailscale 包还未被 feeds install"
    fi
fi

# ==========================================
# 第8步：更新和安装 feeds（必须放在版本修改之后）
# ==========================================
echo ""
echo "========================================"
echo "第8步：更新和安装 feeds 软件包"
echo "========================================"
echo "📥 正在更新 feeds..."
./scripts/feeds update -a
echo "📦 正在安装 feeds..."
./scripts/feeds install -a

echo ""
echo "========================================"
echo "✅ 自定义配置脚本执行完成！"
echo "========================================"
echo ""
echo "📋 配置总结："
echo "  - ✅ Passwall 及依赖（最新 main 分支）"
echo "  - ✅ Xray-core 已更新至最新 GitHub 版本"
echo "  - ✅ Sing-box 已更新至最新 GitHub 版本"  
echo "  - ✅ Tailscale 已更新至最新 GitHub 版本"
echo "  - ✅ Feeds 已更新和安装完成"
echo ""
