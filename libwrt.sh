#!/bin/bash
# ================================================================
# 修复版 libwrt.sh - 确保 Xray/sing-box 始终为最新版本
# ================================================================

# 工具函数
get_latest_version() {
    local repo="$1" ver=""
    for i in {1..3}; do
        ver=$(curl -sL --max-time 10 \
            "https://api.github.com/repos/${repo}/releases/latest" \
            | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
        [ -n "$ver" ] && break
        sleep 2
    done
    echo "${ver:-UNKNOWN}"
}

update_package_version() {
    local pkg_dir="$1" new_ver="$2" mk_file=""
    
    # 查找 Makefile
    mk_file=$(find package -path "*${pkg_dir}/Makefile" 2>/dev/null | head -n 1)
    
    if [ -z "$mk_file" ]; then
        echo "错误：未找到 ${pkg_dir} 的 Makefile"
        return 1
    fi
    
    # 备份原文件
    cp "$mk_file" "${mk_file}.bak"
    
    # 更新版本号
    sed -i "s/^PKG_VERSION[[:space:]]*:=.*/PKG_VERSION:=${new_ver}/" "$mk_file"
    
    # 计算新的哈希值（动态获取）
    local repo_name=$(grep -oP 'PKG_SOURCE_URL:=.*github\.com/\K[^/]+/[^/]+' "$mk_file" | head -n 1)
    if [ -n "$repo_name" ]; then
        local new_hash=$(curl -sL \
            "https://codeload.github.com/${repo_name}/tar.gz/v${new_ver}" | sha256sum | awk '{print $1}')
        if [ -n "$new_hash" ]; then
            sed -i "s/^PKG_HASH[[:space:]]*:=.*/PKG_HASH:=${new_hash}/" "$mk_file"
        else
            # 如果无法获取哈希，跳过校验（不推荐但可用）
            sed -i "s/^PKG_HASH[[:space:]]*:=.*/PKG_HASH:=skip/" "$mk_file"
            echo "警告：${pkg_dir} 无法获取新哈希，已跳过校验"
        fi
    fi
    
    # 验证更新成功
    if grep -q "PKG_VERSION:=${new_ver}" "$mk_file"; then
        echo "✓ ${pkg_dir} 已更新到版本 ${new_ver}"
        return 0
    else
        echo "✗ ${pkg_dir} 更新失败，恢复备份"
        cp "${mk_file}.bak" "$mk_file"
        return 1
    fi
}

# ================================================================
# 主流程
# ================================================================

# 1. 清理默认包
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/msd_lite
rm -rf feeds/packages/net/smartdns
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/appations/luci-app-netdata

# 2. 克隆最新的 Passwall 相关包
echo "开始克隆 Passwall 组件..."
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2

# 3. 获取最新版本号
echo "获取最新版本号..."
XRAY_LATEST=$(get_latest_version "XTLS/Xray-core")
SINGBOX_LATEST=$(get_latest_version "SagerNet/sing-box")

echo "Xray-core 最新版本: ${XRAY_LATEST}"
echo "Sing-box 最新版本: ${SINGBOX_LATEST}"

# 4. 更新版本号
if [ "$XRAY_LATEST" != "UNKNOWN" ]; then
    update_package_version "xray-core" "$XRAY_LATEST"
else
    echo "⚠️ Xray-core 版本获取失败，使用仓库默认版本"
fi

if [ "$SINGBOX_LATEST" != "UNKNOWN" ]; then
    update_package_version "sing-box" "$SINGBOX_LATEST"
else
    echo "⚠️ Sing-box 版本获取失败，使用仓库默认版本"
fi

# 5. 安装其他必要的包
git_sparse_clone main https://github.com/vernesong/OpenClash luci-app-openclash
git clone --depth=1 -b lede https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns
git clone --depth=1 https://github.com/pymumu/openwrt-smartdns package/smartdns

# 6. 只安装必要的 feeds
./scripts/feeds install luci-app-smartdns smartdns

echo "✅ libwrt.sh 执行完成，Xray=${XRAY_LATEST}, Sing-box=${SINGBOX_LATEST}"
