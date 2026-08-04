#!/bin/bash 

ssh_key="$(cat /root/.ssh/id_rsa.pub)"


# 检查containerd是否安装,停止containerd服务
stop_containerd() {
    echo "== stop containerd ..."
    # 检查 containerd 是否已安装
    if ! command -v containerd &> /dev/null; then
        echo "== containerd 未安装，跳过停止"
        echo ""
        return 0
    fi
    # 检查 containerd 服务是否存在
    if ! systemctl list-unit-files | grep -q containerd.service; then
        echo "== containerd 服务不存在，跳过停止"
        echo ""
        return 0
    fi
    # 检查服务状态
    if systemctl is-active --quiet containerd; then
        echo "== containerd 正在运行，停止中..."
        if systemctl stop containerd; then
            echo "== containerd 已停止"
        else
            echo "== containerd 停止失败"
            return 1
        fi
    else
        echo "== containerd 已停止，无需操作"
    fi
    echo ""
    return 0
}

# 免密
ssh_copy(){
        echo "== ssh_copy ..."
        grep -q "$ssh_key" /root/.ssh/authorized_keys &> /dev/null  && echo "== 免密已存在 跳过" && echo "" && return
        mkdir -p /root/.ssh
        echo "$ssh_key" >>/root/.ssh/authorized_keys
        chmod 700 /root/.ssh
        chmod 600 /root/.ssh/authorized_keys
        grep -q "$ssh_key" /root/.ssh/authorized_keys && echo "== OK ==" && echo "" || { echo "== ssh_copy_31 error! exit 1"; exit 1; }
}


#关闭防火墙和selinux
disable_firewalld(){
        echo "== disable_firewalld ..."
    swapoff -a &> /dev/null
    sed -i 's/.*swap.*/#&/' /etc/fstab &> /dev/null
    iptables -P FORWARD ACCEPT &> /dev/null
    systemctl stop firewalld &> /dev/null
    systemctl disable firewalld &> /dev/null
        systemctl stop ufw &> /dev/null
    systemctl disable ufw &> /dev/null
    sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config &> /dev/null
    setenforce 0 &> /dev/null
    sed -ri 's/1/0/' /etc/yum/pluginconf.d/license-manager.conf &> /dev/null
        # 修改时区 
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &> /dev/null  #或  timedatectl set-timezone "Asia/Shanghai"
        # 修改为24小时制
        sudo locale-gen en_DK.UTF-8 &> /dev/null
        echo "LC_TIME=en_DK.UTF-8" >> /etc/default/locale &> /dev/null
        echo "== 完成 ==" && echo ""
}


modify_sysctl(){
echo "== 修改内核参数 ..."

# 1. 处理sysctl配置（/etc/sysctl.d/k8s.conf）
SYSCTL_CONF="/etc/sysctl.d/k8s.conf"
# 定义要添加的sysctl配置内容（新增fs.inotify.max_user_instances=4096）
SYSCTL_CONTENT=$(cat <<-'EOF'
vm.swappiness=0
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.ip_local_port_range = 1024     65000
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.neigh.default.gc_thresh1=4096
net.ipv4.neigh.default.gc_thresh2=6144
net.ipv4.neigh.default.gc_thresh3=8192
fs.inotify.max_user_instances = 4096
EOF
)

# 检查关键配置项是否已存在（避免重复添加）
# 新增检查fs.inotify.max_user_instances=4096
if ! grep -q "vm.swappiness=0" "$SYSCTL_CONF" &> /dev/null || \
   ! grep -q "net.ipv4.ip_forward=1" "$SYSCTL_CONF" &> /dev/null || \
   ! grep -q "net.bridge.bridge-nf-call-iptables=1" "$SYSCTL_CONF" &> /dev/null || \
   ! grep -q "fs.inotify.max_user_instances = 4096" "$SYSCTL_CONF" &> /dev/null; then
    echo "== 写入sysctl配置到 $SYSCTL_CONF ..."
    echo "$SYSCTL_CONTENT" >> "$SYSCTL_CONF"
else
    echo "== sysctl配置已存在，跳过写入 ..."
fi


cat <<-'EOF' >> /etc/sysctl.d/k8s.conf
fs.inotify.max_user_instances=4096
fs.inotify.max_user_watches=1048576
EOF


# 加载br_netfilter模块（仅当未加载时）
if ! lsmod | grep -q "br_netfilter"; then
    echo "== 加载br_netfilter模块 ..."
    modprobe br_netfilter
else
    echo "== br_netfilter模块已加载，跳过 ..."
fi

# 生效sysctl配置
sysctl --system

# 2. 处理内核模块加载配置（/etc/modules-load.d/k8s.conf）
MODULES_CONF="/etc/modules-load.d/k8s.conf"
MODULES_CONTENT=$(cat <<-'EOF'
br_netfilter
overlay
EOF
)

# 检查模块配置文件是否存在且内容完整
if [ ! -f "$MODULES_CONF" ] || ! grep -q "br_netfilter" "$MODULES_CONF" &> /dev/null || ! grep -q "overlay" "$MODULES_CONF" &> /dev/null; then
    echo "== 写入模块加载配置到 $MODULES_CONF ..."
    tee "$MODULES_CONF" <<< "$MODULES_CONTENT" > /dev/null
else
    echo "== 模块加载配置已存在，跳过写入 ..."
fi

# 加载overlay模块（仅当未加载时）
if ! lsmod | grep -q "overlay"; then
    echo "== 加载overlay模块 ..."
    modprobe overlay
else
    echo "== overlay模块已加载，跳过 ..."
fi

# 3. 处理nofile句柄数配置，单个进程可打开文件句柄数
NOFILE_CONF="/etc/security/limits.d/nofile.conf"
NOFILE_LINES=(
    "*      soft   nofile 102400"
    "*      hard   nofile 102400"
    "root   soft   nofile unlimited"
)

for line in "${NOFILE_LINES[@]}"; do
    if ! grep -qxF "$line" "$NOFILE_CONF" &> /dev/null; then  # -xF: 精确匹配整行
        echo "== 追加nofile配置行：$line ..."
        echo "$line" >> "$NOFILE_CONF"
    else
        echo "== nofile配置行已存在：$line，跳过 ..."
    fi
done

# 4. 处理nproc进程数配置，单个用户可打开文件句柄数
NPROC_CONF="/etc/security/limits.d/nproc.conf"
NPROC_LINES=(
    "*      soft   nproc 102400"
    "*      hard   nproc 102400"
    "root   soft   nproc unlimited"
)

for line in "${NPROC_LINES[@]}"; do
    if ! grep -qxF "$line" "$NPROC_CONF" &> /dev/null; then  # -xF: 精确匹配整行
        echo "== 追加nproc配置行：$line ..."
        echo "$line" >> "$NPROC_CONF"
    else
        echo "== nproc配置行已存在：$line，跳过 ..."
    fi
done

# 5. 处理 /etc/rc.local 中的 ulimit 配置（确保开机生效 nofile）
RC_LOCAL="/etc/rc.local"
ULIMIT_LINE="ulimit -SHn 102400"

# 确保 rc.local 文件存在
if [ ! -f "$RC_LOCAL" ]; then
    echo "#!/bin/bash" > "$RC_LOCAL"
    echo "== 创建 $RC_LOCAL 文件 ..."
fi

# 检查 ulimit 配置行是否已存在，不存在则追加
if ! grep -qxF "$ULIMIT_LINE" "$RC_LOCAL" &> /dev/null; then
    echo "== 追加 ulimit 配置到 $RC_LOCAL ..."
    echo "$ULIMIT_LINE" >> "$RC_LOCAL"
else
    echo "== ulimit 配置行已存在于 $RC_LOCAL，跳过 ..."
fi

# 确保 rc.local 有执行权限（直接对 $RC_LOCAL 操作）
if [ ! -x "$RC_LOCAL" ]; then
    echo "== 赋予 $RC_LOCAL 执行权限 ..."
    chmod +x "$RC_LOCAL"
else
    echo "== $RC_LOCAL 已有执行权限，跳过 ..."
fi


# 1. 将 system.slice 的内存限制设置为无限制
systemctl set-property system.slice MemoryMax=infinity &> /dev/null

# 永久解除 system.slice 内存限制
systemctl set-property system.slice MemoryLimit=infinity &> /dev/null

# 同步解除 docker 服务限制
systemctl set-property docker.service MemoryLimit=infinity &> /dev/null

# 重载 systemd 配置（立即生效）
systemctl daemon-reexec &> /dev/null

# 查看当前限制
systemctl show system.slice --property=MemoryMax
}


main(){
    stop_containerd
        ssh_copy
    disable_firewalld
    modify_sysctl
}

main $* && echo "==== 初始化完成~ ====" || echo "==== 初始化失败，请检查错误！ ===="
