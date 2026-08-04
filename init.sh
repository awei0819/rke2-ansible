#!/bin/bash
# ============================================================
# 通用 Linux 节点初始化脚本 (适用于 RKE2/K8s)
# 支持: Ubuntu, CentOS, RHEL, Debian, 麒麟 (Kylin) 等
# ============================================================

set -e  # 遇到错误即退出，便于发现失败

# ---------- 全局变量 ----------
SSH_KEY=""

# ---------- 工具函数 ----------
# 检测当前系统类型 (ubuntu, centos, debian, kylin, rhel 等)
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        OS=$(uname -s)
    fi
    echo "$OS" | tr '[:upper:]' '[:lower:]'
}

OS=$(detect_os)
echo "== 检测到系统: $OS"

# 安全设置 sysctl（只设置存在的键）
safe_sysctl_set() {
    local key="$1"
    local value="$2"
    if sysctl -a 2>/dev/null | grep -q "^${key} "; then
        sysctl -w "$key=$value" 2>/dev/null || true
    else
        echo "== 警告: sysctl 参数 $key 不存在，跳过"
    fi
}

# 加载内核模块（兼容不同名称）
load_module() {
    local mod="$1"
    local mod_alt="$2"   # 备选模块名
    if lsmod | grep -q "$mod"; then
        echo "== 模块 $mod 已加载"
        return 0
    fi
    if modprobe "$mod" 2>/dev/null; then
        echo "== 加载模块 $mod 成功"
        return 0
    elif [ -n "$mod_alt" ] && modprobe "$mod_alt" 2>/dev/null; then
        echo "== 加载备选模块 $mod_alt 成功（替代 $mod）"
        return 0
    else
        echo "== 警告: 无法加载模块 $mod（可能无需加载）"
        return 1
    fi
}


# ---------- 1. 停止 containerd（如存在） ----------
stop_containerd() {
    echo "== stop containerd ..."
    if ! command -v containerd &>/dev/null; then
        echo "== containerd 未安装，跳过"
        return 0
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q containerd.service; then
        if systemctl is-active --quiet containerd; then
            echo "== containerd 正在运行，停止中..."
            systemctl stop containerd && echo "== containerd 已停止"
        else
            echo "== containerd 已停止"
        fi
    else
        echo "== containerd 服务不存在，跳过"
    fi
    echo ""
}

# ---------- 2. 配置 SSH 免密登录 ----------
ssh_copy() {
    echo "== ssh_copy ..."
    if grep -q "$SSH_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
        echo "== 免密已存在，跳过"
        echo ""
        return
    fi
    mkdir -p /root/.ssh
    echo "$SSH_KEY" >> /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    if grep -q "$SSH_KEY" /root/.ssh/authorized_keys; then
        echo "== OK =="
    else
        echo "== ssh_copy 失败！退出"
        exit 1
    fi
    echo ""
}

# ---------- 3. 关闭防火墙 & 交换分区 ----------
disable_firewall() {
    echo "== disable_firewalld / ufw ..."
    # 关闭 swap
    swapoff -a &>/dev/null
    sed -i '/swap/s/^/#/' /etc/fstab &>/dev/null || true

    # 关闭防火墙 (兼容 firewalld, ufw)
    if systemctl list-unit-files 2>/dev/null | grep -q firewalld.service; then
        systemctl stop firewalld &>/dev/null && echo "== firewalld 已停止"
        systemctl disable firewalld &>/dev/null && echo "== firewalld 已禁用"
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q ufw.service; then
        systemctl stop ufw &>/dev/null && echo "== ufw 已停止"
        systemctl disable ufw &>/dev/null && echo "== ufw 已禁用"
    fi
    # 设置 iptables 转发策略
    iptables -P FORWARD ACCEPT &>/dev/null

    # SELinux (仅针对 RHEL/CentOS 系列)
    if [ -f /etc/selinux/config ]; then
        sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config &>/dev/null
        setenforce 0 &>/dev/null || true
        echo "== SELinux 已禁用"
    fi

    # 时区设置为上海 (通用)
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "== 时区已设置为 Asia/Shanghai"

    echo "== 防火墙/swap 处理完成"
    echo ""
}

# ---------- 4. 内核参数调优 ----------
modify_sysctl() {
    echo "== 修改内核参数 ..."

    # 加载必要内核模块 (overlay, br_netfilter)
    load_module overlay
    load_module br_netfilter bridge   # 备选 bridge

    # 写入核心 sysctl 配置（只写必要项）
    SYSCTL_CONF="/etc/sysctl.d/k8s.conf"
    cat > "$SYSCTL_CONF" <<-'EOF'
# Kubernetes required sysctl settings
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
vm.swappiness = 0
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.neigh.default.gc_thresh1 = 4096
net.ipv4.neigh.default.gc_thresh2 = 6144
net.ipv4.neigh.default.gc_thresh3 = 8192
fs.inotify.max_user_instances = 4096
fs.inotify.max_user_watches = 1048576
EOF

    # 应用配置（仅应用本文件，避免系统默认文件的错误）
    sysctl -p "$SYSCTL_CONF" 2>/dev/null || echo "== 警告: 部分 sysctl 参数设置失败，但核心参数已生效"

    # 配置 limits (nofile, nproc)
    LIMITS_CONF="/etc/security/limits.d/99-k8s.conf"
    cat > "$LIMITS_CONF" <<-'EOF'
*      soft   nofile 102400
*      hard   nofile 102400
root   soft   nofile unlimited
*      soft   nproc 102400
*      hard   nproc 102400
root   soft   nproc unlimited
EOF
    echo "== limits 配置已写入 $LIMITS_CONF"

    # rc.local ulimit 设置 (兼容老旧系统)
    RC_LOCAL="/etc/rc.local"
    if [ ! -f "$RC_LOCAL" ]; then
        echo '#!/bin/bash' > "$RC_LOCAL"
        chmod +x "$RC_LOCAL"
    fi
    if ! grep -q "ulimit -SHn 102400" "$RC_LOCAL" 2>/dev/null; then
        echo "ulimit -SHn 102400" >> "$RC_LOCAL"
        echo "== ulimit 已追加到 $RC_LOCAL"
    fi

    # systemd 内存限制解除 (不影响功能)
    systemctl set-property system.slice MemoryMax=infinity &>/dev/null || true
    systemctl set-property system.slice MemoryLimit=infinity &>/dev/null || true
    systemctl set-property docker.service MemoryLimit=infinity &>/dev/null || true
    systemctl daemon-reexec &>/dev/null || true

    echo "== 内核参数修改完成"
    echo ""
}

# ---------- 主流程 ----------
main() {
    stop_containerd
    ssh_copy
    disable_firewall
    modify_sysctl
    echo "==== 初始化完成~ ===="
}

main "$@"
