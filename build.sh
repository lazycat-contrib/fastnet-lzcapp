#!/bin/bash

# =============================================================================
# FastNet LazyCat 应用自动化发布脚本
# =============================================================================
# 功能：
# 1. 构建应用 LPK 包
# 2. 复制镜像到懒猫仓库
# 3. 发布到应用商店
# 4. 一键完整发布流程
# =============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
APP_NAME="FastNet"
PACKAGE_NAME="cloud.lazycat.app.fastnet"
MANIFEST_FILE="lzc-manifest.yml"
BUILD_FILE="lzc-build.yml"
ORIGINAL_IMAGE="xkand/fastnet"

# 从 manifest 中读取版本号
get_version() {
    if [ -f "$MANIFEST_FILE" ]; then
        grep "^version:" "$MANIFEST_FILE" | awk '{print $2}' | tr -d '"' | tr -d "'"
    else
        echo "1.0.0"
    fi
}

VERSION=$(get_version)
OUTPUT_FILE="fastnet-${VERSION}.lpk"

# 打印函数
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 检查必需文件
check_files() {
    print_header "检查必需文件"

    local missing_files=()

    if [ ! -f "$MANIFEST_FILE" ]; then
        missing_files+=("$MANIFEST_FILE")
    fi

    if [ ! -f "$BUILD_FILE" ]; then
        missing_files+=("$BUILD_FILE")
    fi

    if [ ! -f "icon.png" ]; then
        print_warning "缺少 icon.png 文件"
        print_info "请准备一个 512x512 的 PNG 图标文件"
        missing_files+=("icon.png")
    fi

    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "缺少必需文件:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        return 1
    fi

    print_success "所有必需文件已就绪"
    return 0
}

# 验证配置
validate_config() {
    print_header "验证配置文件"

    # 检查 YAML 格式
    if command -v yq &> /dev/null; then
        if yq eval '.' "$MANIFEST_FILE" > /dev/null 2>&1; then
            print_success "manifest 格式正确"
        else
            print_error "manifest 格式错误"
            return 1
        fi
    else
        print_info "未安装 yq，跳过 YAML 格式检查"
    fi

    # 检查必需字段
    if ! grep -q "^name:" "$MANIFEST_FILE"; then
        print_error "manifest 缺少 name 字段"
        return 1
    fi

    if ! grep -q "^package:" "$MANIFEST_FILE"; then
        print_error "manifest 缺少 package 字段"
        return 1
    fi

    if ! grep -q "^version:" "$MANIFEST_FILE"; then
        print_error "manifest 缺少 version 字段"
        return 1
    fi

    print_success "配置验证通过"
    return 0
}

# 显示应用信息
show_info() {
    print_header "应用信息"

    echo "应用名称: $APP_NAME"
    echo "包名: $PACKAGE_NAME"
    echo "版本: $VERSION"
    echo "原始镜像: $ORIGINAL_IMAGE"
    echo "输出文件: $OUTPUT_FILE"
    echo ""

    if [ -f "$MANIFEST_FILE" ]; then
        echo "Manifest 内容概览:"
        echo "---"
        head -20 "$MANIFEST_FILE"
        echo "---"
    fi
}

# 构建应用
build_app() {
    print_header "构建应用"

    # 检查文件
    if ! check_files; then
        return 1
    fi

    # 验证配置
    if ! validate_config; then
        return 1
    fi

    print_info "开始构建 LPK 包: $OUTPUT_FILE"

    if lzc-cli project build -o "$OUTPUT_FILE"; then
        print_success "构建成功: $OUTPUT_FILE"

        # 显示文件信息
        if [ -f "$OUTPUT_FILE" ]; then
            size=$(du -h "$OUTPUT_FILE" | awk '{print $1}')
            print_info "包大小: $size"
        fi

        return 0
    else
        print_error "构建失败"
        return 1
    fi
}

# 复制镜像到懒猫仓库
copy_image() {
    print_header "复制镜像到懒猫仓库"

    # 检查登录状态
    print_info "检查登录状态..."
    if ! lzc-cli appstore my-images &> /dev/null 2>&1; then
        print_warning "未登录懒猫应用商店"
        print_info "请先执行: lzc-cli appstore login"
        return 1
    fi

    print_info "正在复制镜像: $ORIGINAL_IMAGE"
    print_warning "这可能需要几分钟，请耐心等待..."

    # 执行镜像复制
    result=$(lzc-cli appstore copy-image "$ORIGINAL_IMAGE" 2>&1)

    if echo "$result" | grep -q "lazycat-registry:"; then
        # 提取新镜像地址
        new_image=$(echo "$result" | grep "lazycat-registry:" | sed 's/.*lazycat-registry: //')

        print_success "镜像复制成功"
        print_info "新镜像地址: $new_image"

        # 自动更新 manifest
        print_info "正在更新 manifest 文件..."
        update_manifest_image "$new_image"

        return 0
    else
        print_error "镜像复制失败"
        echo "$result"
        return 1
    fi
}

# 更新 manifest 中的镜像地址
update_manifest_image() {
    local new_image="$1"

    if [ -z "$new_image" ]; then
        print_error "镜像地址为空"
        return 1
    fi

    # 备份原文件
    cp "$MANIFEST_FILE" "${MANIFEST_FILE}.bak"

    # 更新镜像地址
    if sed -i.tmp "s|image: .*|image: $new_image|g" "$MANIFEST_FILE"; then
        rm -f "${MANIFEST_FILE}.tmp"
        print_success "Manifest 已更新"
        print_info "请查看 $MANIFEST_FILE 确认更改"

        # 显示更改
        echo ""
        echo "更新后的镜像配置:"
        grep "image:" "$MANIFEST_FILE"
        echo ""

        return 0
    else
        # 恢复备份
        mv "${MANIFEST_FILE}.bak" "$MANIFEST_FILE"
        print_error "更新 manifest 失败，已恢复原文件"
        return 1
    fi
}

# 发布到应用商店
publish_app() {
    print_header "发布到应用商店"

    # 检查 LPK 文件
    if [ ! -f "$OUTPUT_FILE" ]; then
        print_error "LPK 文件不存在: $OUTPUT_FILE"
        print_info "请先构建应用"
        return 1
    fi

    # 检查登录状态
    print_info "检查登录状态..."
    if ! lzc-cli appstore my-images &> /dev/null 2>&1; then
        print_warning "未登录懒猫应用商店"
        print_info "请先执行: lzc-cli appstore login"
        return 1
    fi

    print_info "正在发布应用: $OUTPUT_FILE"

    if lzc-cli appstore publish "$OUTPUT_FILE"; then
        print_success "发布成功"
        print_info "请等待 1-3 天审核"
        return 0
    else
        print_error "发布失败"
        return 1
    fi
}

# 一键完整发布流程
one_click_publish() {
    print_header "🚀 一键完整发布流程"

    print_info "这将执行完整的 4 阶段发布流程:"
    echo "  阶段 1: 初始构建（原始镜像）"
    echo "  阶段 2: 镜像复制（自动更新 manifest）"
    echo "  阶段 3: 重新构建（新镜像）"
    echo "  阶段 4: 发布审核"
    echo ""

    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "已取消"
        return 1
    fi

    # 阶段 1: 初始构建
    print_header "阶段 1/4: 初始构建（原始镜像）"
    if ! build_app; then
        print_error "阶段 1 失败"
        return 1
    fi

    # 阶段 2: 镜像复制
    print_header "阶段 2/4: 镜像复制（自动更新 manifest）"
    if ! copy_image; then
        print_error "阶段 2 失败"
        return 1
    fi

    # 阶段 3: 重新构建
    print_header "阶段 3/4: 重新构建（新镜像）"
    if ! build_app; then
        print_error "阶段 3 失败"
        return 1
    fi

    # 阶段 4: 发布
    print_header "阶段 4/4: 发布审核"
    if ! publish_app; then
        print_error "阶段 4 失败"
        return 1
    fi

    print_header "✅ 完整发布流程成功"
    print_success "应用已提交审核，请等待 1-3 天"
}

# 主菜单
show_menu() {
    echo ""
    print_header "FastNet 懒猫应用发布工具"
    echo ""
    echo "1. 📦 构建应用 (Build)"
    echo "2. 🔧 镜像复制到懒猫仓库 (Copy Image)"
    echo "3. 📤 发布到应用商店 (Publish)"
    echo "4. 🚀 一键构建+镜像复制+发布 (One-Click)"
    echo "5. 📋 查看应用信息 (Info)"
    echo "6. ❌ 退出"
    echo ""
}

# 主程序
main() {
    # 如果有命令行参数，直接执行对应操作
    if [ $# -gt 0 ]; then
        case "$1" in
            build)
                build_app
                ;;
            copy)
                copy_image
                ;;
            publish)
                publish_app
                ;;
            one-click)
                one_click_publish
                ;;
            info)
                show_info
                ;;
            *)
                print_error "未知命令: $1"
                echo "可用命令: build, copy, publish, one-click, info"
                exit 1
                ;;
        esac
        exit $?
    fi

    # 交互式菜单
    while true; do
        show_menu
        read -p "请选择操作 (1-6): " choice

        case $choice in
            1)
                build_app
                ;;
            2)
                copy_image
                ;;
            3)
                publish_app
                ;;
            4)
                one_click_publish
                ;;
            5)
                show_info
                ;;
            6)
                print_info "再见！"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 1-6"
                ;;
        esac

        echo ""
        read -p "按回车键继续..."
    done
}

# 执行主程序
main "$@"
