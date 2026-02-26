#!/bin/bash
#
# RKE2 离线安装包下载脚本
# 用法: ./download_rke2_artifacts.sh --arch amd64 --release v1.34.2+rke2r1
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认值
ARCH=""
RELEASE=""

# 打印帮助信息
print_help() {
    echo "用法: $0 --arch <amd64|arm64> --release <version>"
    echo ""
    echo "参数:"
    echo "  --arch, -a      架构类型 (amd64 或 arm64)"
    echo "  --release, -r   K8S+RKE2 版本号 (例如: v1.34.2+rke2r1)"
    echo "  --help, -h      显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --arch amd64 --release v1.34.2+rke2r1"
    echo "  $0 -a arm64 -r v1.31.6+rke2r1"
    echo ""
    echo "输出:"
    echo "  rke2-artifacts-{arch}-{version}.tgz"
    echo ""
    echo "下载的文件:"
    echo "  - rke2-images.linux-{arch}.tar.zst      (核心镜像)"
    echo "  - rke2-images-calico.linux-{arch}.tar.zst (Calico镜像，可选)"
    echo "  - rke2.linux-{arch}.tar.gz              (二进制文件)"
    echo "  - sha256sum-{arch}.txt                  (校验文件)"
    echo "  - install.sh                            (安装脚本)"
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --arch|-a)
                ARCH="$2"
                shift 2
                ;;
            --release|-r)
                RELEASE="$2"
                shift 2
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知参数 $1${NC}"
                print_help
                exit 1
                ;;
        esac
    done
}

# 验证参数
validate_args() {
    if [ -z "$ARCH" ]; then
        echo -e "${RED}错误: 必须指定 --arch 参数 (amd64 或 arm64)${NC}"
        print_help
        exit 1
    fi

    if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "arm64" ]; then
        echo -e "${RED}错误: --arch 必须是 amd64 或 arm64${NC}"
        exit 1
    fi

    if [ -z "$RELEASE" ]; then
        echo -e "${RED}错误: 必须指定 --release 参数${NC}"
        print_help
        exit 1
    fi
}

# URL 编码版本号 (+ 替换为 %2B)
encode_version() {
    echo "$1" | sed 's/+/%2B/g'
}

# 下载文件并显示进度
download_file() {
    local url=$1
    local output_file=$2
    local description=$3

    echo -e "${BLUE}正在下载: ${description}${NC}"
    echo -e "  URL: ${url}"

    if wget --progress=bar:force -O "$output_file" "$url" 2>&1; then
        echo -e "${GREEN}✓ 下载完成: ${output_file}${NC}"
        return 0
    else
        echo -e "${RED}✗ 下载失败: ${output_file}${NC}"
        return 1
    fi
}

# 主函数
main() {
    parse_args "$@"
    validate_args

    # 编码版本号
    ENCODED_RELEASE=$(encode_version "$RELEASE")
    
    # 清理版本号中的 + 用于目录名
    CLEAN_RELEASE=$(echo "$RELEASE" | sed 's/+/-/g')

    # 创建目录名
    DIR_NAME="rke2-artifacts"
    TAR_NAME="${DIR_NAME}-${ARCH}-${CLEAN_RELEASE}.tgz"

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}RKE2 离线安装包下载工具${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "架构:     ${YELLOW}${ARCH}${NC}"
    echo -e "版本:     ${YELLOW}${RELEASE}${NC}"
    echo -e "输出目录: ${YELLOW}${DIR_NAME}/${NC}"
    echo -e "输出文件: ${YELLOW}${TAR_NAME}${NC}"
    echo ""

    # 创建目录
    if [ -d "$DIR_NAME" ]; then
        echo -e "${YELLOW}目录已存在，将被覆盖: ${DIR_NAME}${NC}"
        rm -rf "$DIR_NAME"
    fi
    mkdir -p "$DIR_NAME"
    cd "$DIR_NAME"

    # GitHub 下载基础 URL
    BASE_URL="https://github.com/rancher/rke2/releases/download/${ENCODED_RELEASE}"

    # 下载文件列表
    declare -A FILES=(
        ["rke2-images.linux-${ARCH}.tar.zst"]="核心镜像包"
        ["rke2-images-calico.linux-${ARCH}.tar.zst"]="Calico CNI 镜像包"
        ["rke2.linux-${ARCH}.tar.gz"]="RKE2 二进制文件"
        ["sha256sum-${ARCH}.txt"]="SHA256 校验文件"
    )

    # 下载所有文件
    DOWNLOAD_FAILED=0
    for file in "${!FILES[@]}"; do
        description="${FILES[$file]}"
        url="${BASE_URL}/${file}"
        
        if download_file "$url" "$file" "$description"; then
            :
        else
            DOWNLOAD_FAILED=1
        fi
        echo ""
    done

    # 下载安装脚本 (从国内镜像)
    echo -e "${BLUE}正在下载: 安装脚本 ${NC}"
    if wget --no-check-certificate -O install.sh "https://rancher-mirror.rancher.cn/rke2/install.sh" 2>&1; then
        chmod +x install.sh
        echo -e "${GREEN}✓ 下载完成: install.sh${NC}"
    else
        echo -e "${YELLOW}! 国内镜像下载失败，尝试 GitHub...${NC}"
        if wget -O install.sh "https://raw.githubusercontent.com/rancher/rke2/master/install.sh" 2>&1; then
            chmod +x install.sh
            echo -e "${GREEN}✓ 下载完成: install.sh${NC}"
        else
            echo -e "${RED}✗ 安装脚本下载失败${NC}"
            DOWNLOAD_FAILED=1
        fi
    fi
    echo ""

    # 如果下载失败，退出
    if [ $DOWNLOAD_FAILED -eq 1 ]; then
        echo -e "${RED}部分文件下载失败，请检查版本号是否正确${NC}"
        exit 1
    fi

    # 显示下载的文件
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}下载完成，文件列表:${NC}"
    echo -e "${GREEN}========================================${NC}"
    ls -lh
    echo ""

    # 计算总大小
    TOTAL_SIZE=$(du -sh . | cut -f1)
    echo -e "总大小: ${YELLOW}${TOTAL_SIZE}${NC}"
    echo ""

    # 返回上级目录并打包
    cd ..
    
    echo -e "${BLUE}正在打包: ${TAR_NAME}${NC}"
    tar czvf "$TAR_NAME" "$DIR_NAME"
    
    TAR_SIZE=$(ls -lh "$TAR_NAME" | awk '{print $5}')
    echo -e "${GREEN}✓ 打包完成: ${TAR_NAME} (${TAR_SIZE})${NC}"
    echo ""

    # 删除下载目录
    rm -rf ${DIR_NAME}

    # 显示最终结果
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}全部完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "离线安装包: ${YELLOW}${TAR_NAME}${NC}"
    echo ""
}

# 执行主函数
main "$@"
