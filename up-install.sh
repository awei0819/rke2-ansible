#!/bin/bash

# ============ YAML 值提取工具（锚定 key + 剥注释 + 去首尾空白/引号） ============
yaml_get() {
    local key="$1"
    grep -E "^[[:space:]]*${key}[[:space:]]*:" cluster.yaml \
        | head -1 \
        | sed 's/[[:space:]]*#.*//' \
        | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" \
        | sed -E 's/[[:space:]]+$//' \
        | sed -E "s/^[\"']//; s/[\"']$//"
}

# ============ 读取 cluster.yaml 基础配置 ============
rke2_data_dir=$(yaml_get data_dir)
CNI=$(yaml_get cni)
Calico_Net=$(yaml_get calico_net)
master_ingress=$(yaml_get master_ingress)
worker_ingress=$(yaml_get worker_ingress)
Local_Address=$(yaml_get local_address)

# ============ 提取 master/worker 列表（兼容任意缩进 + 剥注释） ============
Master_List_Port=$(sed -n '/^master:/{n; :a; /^[[:space:]]*-[[:space:]]/p; n; /^[[:space:]]*-[[:space:]]/ba}' cluster.yaml \
    | sed 's/[[:space:]]*#.*//' \
    | awk '{print $NF}')
Worker_List_Port=$(sed -n '/^worker:/{n; :a; /^[[:space:]]*-[[:space:]]/p; n; /^[[:space:]]*-[[:space:]]/ba}' cluster.yaml \
    | sed 's/[[:space:]]*#.*//' \
    | awk '{print $NF}')

# 由带端口的列表派生纯 IP 列表
Master_List=$(echo "$Master_List_Port" | sed 's/:.*//')
Worker_List=$(echo "$Worker_List_Port" | sed 's/:.*//')

All_Nodes="
$Master_List
$Worker_List
"
All_Nodes_Port="
$Master_List_Port
$Worker_List_Port
"

# ============ SSH 公共参数（所有 ssh 调用统一引用） ============
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# ============ 校验 local_address 必须在 master 列表中 ============
if ! echo "$Master_List" | grep -qx "$Local_Address"; then
    echo "错误: local_address ($Local_Address) 不在 master 列表中！" >&2
    echo "master 列表: $Master_List" >&2
    exit 1
fi

# ============ 从 master 列表解析 local_address 的端口 ============
Local_Port=$(
    echo "$Master_List_Port" \
    | tr ' ' '\n' \
    | grep "^${Local_Address}:" \
    | head -1 \
    | awk -F':' '{print $NF}'
)

# ============ 端口防御校验 ============
if [[ -z "$Local_Port" ]] || ! [[ "$Local_Port" =~ ^[0-9]+$ ]]; then
    echo "错误: 无法从 master 列表中找到 local_address ($Local_Address) 对应的端口" >&2
    echo "请确认 cluster.yaml 中 master 列表里存在形如 ${Local_Address}:8022 的条目" >&2
    exit 1
fi
echo "== 解析到控制节点: $Local_Address:$Local_Port"

# ---- SSH 连接测试 ----
echo "正在测试与控制节点 $Local_Address:$Local_Port 的 SSH 连接..."
if ! ssh -q $SSH_OPTS -o BatchMode=yes -o ConnectTimeout=5 -p "$Local_Port" "$Local_Address" "exit" 2>/dev/null; then
    echo "错误：无法通过 SSH 连接到 $Local_Address:$Local_Port，请检查网络和认证配置。" >&2
    exit 1
fi
echo "SSH 连接成功。"

# ---- 尝试获取集群节点列表 ----
Get_Nodes_Raw="$(ssh $SSH_OPTS -p "$Local_Port" "$Local_Address" kubectl get node -o wide 2>/dev/null)"
Get_Masters="$(echo "$Get_Nodes_Raw" | egrep "master|control-plane" | awk '{print $6}')"
Get_Workers="$(echo "$Get_Nodes_Raw" | egrep -v "master|control-plane|STATUS" | awk '{print $6}')"
Get_All_Nodes="
$Get_Masters
$Get_Workers
"

# ---- 判断集群状态：区分「初次部署」和「已有集群但 kubectl 异常」 ----
if [[ -z "$Get_Masters" ]]; then
    rke2_state="$(ssh $SSH_OPTS -p "$Local_Port" "$Local_Address" \
        'systemctl is-active rke2-server.service 2>/dev/null || echo inactive')"
    if [[ "$rke2_state" == "active" ]]; then
        echo "错误：$Local_Address rke2-server 处于运行状态，但无法通过 kubectl 获取节点信息。" >&2
        echo "      请检查 API Server 健康状态及 kubeconfig：/etc/rancher/rke2/rke2.yaml" >&2
        exit 1
    fi
    echo "== 未检测到已运行集群，进入初始化部署流程"
fi

# 计算新增的纯IP列表（未在集群中的节点）
New_Masters=$(echo "$Master_List" | tr ' ' '\n' | grep -Fxvf <(echo "$Get_Masters" | tr ' ' '\n') 2> /dev/null)
New_Workers=$(echo "$Worker_List" | tr ' ' '\n' | grep -Fxvf <(echo "$Get_Workers" | tr ' ' '\n') 2> /dev/null)
New_Nodes="
$New_Masters
$New_Workers
"

# 新增master节点:端口
New_Masters_Port=$(
    for ip in $New_Masters; do
        echo "$Master_List_Port" | grep "^${ip}:" | uniq
    done | tr '\n' ' ' | sed 's/ $//'
)
# 新增worker节点:端口
New_Workers_Port=$(
    for ip in $New_Workers; do
        echo "$Worker_List_Port" | grep "^${ip}:" | uniq
    done | tr '\n' ' ' | sed 's/ $//'
)
New_Nodes_Port="
$New_Masters_Port
$New_Workers_Port
"

# 计算需要删除的节点
Del_Masters=$(echo "$Get_Masters" | tr ' ' '\n' | grep -Fxvf <(echo "$Master_List" | tr ' ' '\n') 2> /dev/null)
Del_Workers=$(echo "$Get_Workers" | tr ' ' '\n' | grep -Fxvf <(echo "$Worker_List" | tr ' ' '\n') 2> /dev/null)
Del_Nodes="
$Del_Masters
$Del_Workers
"

# 从hosts/ansible-hosts文件中获取删除节点的端口
Del_Masters_Port=$(
    for ip in $Del_Masters; do
        line=$(grep -E "^${ip}[[:space:]]" hosts/ansible-hosts | head -1)
        if [[ -n "$line" ]]; then
            ip_part=$(echo "$line" | awk '{print $1}')
            port_part=$(echo "$line" | grep -o 'ansible_port=[0-9]*' | cut -d= -f2)
            echo "${ip_part}:${port_part}"
        fi
    done | tr '\n' ' ' | sed 's/ $//'
)

Del_Workers_Port=$(
    for ip in $Del_Workers; do
        line=$(grep -E "^${ip}[[:space:]]" hosts/ansible-hosts | head -1)
        if [[ -n "$line" ]]; then
            ip_part=$(echo "$line" | awk '{print $1}')
            port_part=$(echo "$line" | grep -o 'ansible_port=[0-9]*' | cut -d= -f2)
            echo "${ip_part}:${port_part}"
        fi
    done | tr '\n' ' ' | sed 's/ $//'
)

Del_Nodes_Port="
$Del_Masters_Port
$Del_Workers_Port
"

#-------------- 初始化ansible-hosts文件
init_hosts(){
    echo "==== init ansible-hosts"
    echo "[rke2]" > hosts/ansible-hosts
    for node in $All_Nodes_Port; do
        ip=$(echo "$node" | awk -F':' '{print $1}')
        port=$(echo "$node" | awk -F':' '{print $2}')
        echo "$ip ansible_port=$port" >> hosts/ansible-hosts
    done
    echo "" >> hosts/ansible-hosts

    echo "[rke2-masters]" >> hosts/ansible-hosts
    for node in $Master_List_Port; do
        ip=$(echo "$node" | awk -F':' '{print $1}')
        port=$(echo "$node" | awk -F':' '{print $2}')
        echo "$ip ansible_port=$port" >> hosts/ansible-hosts
    done
    echo "" >> hosts/ansible-hosts

    echo "[rke2-workers]" >> hosts/ansible-hosts
    for node in $Worker_List_Port; do
        ip=$(echo "$node" | awk -F':' '{print $1}')
        port=$(echo "$node" | awk -F':' '{print $2}')
        echo "$ip ansible_port=$port" >> hosts/ansible-hosts
    done

    echo "更新hosts文件:"
    cat hosts/ansible-hosts
    echo ""
}

# 更新新增节点的ansible hosts文件
update_hosts(){
    echo "==== init ansible-hosts-up"
    echo "[rke2]" > hosts/ansible-hosts-up
    for node in $New_Nodes_Port; do
        ip=$(echo "$node" | awk -F':' '{print $1}')
        port=$(echo "$node" | awk -F':' '{print $2}')
        echo "$ip ansible_port=$port" >> hosts/ansible-hosts-up
    done
    echo "" >> hosts/ansible-hosts-up

    echo "[rke2-masters]" >> hosts/ansible-hosts-up
    for node in $New_Masters_Port; do
        ip=$(echo "$node" | awk -F':' '{print $1}')
        port=$(echo "$node" | awk -F':' '{print $2}')
        echo "$ip ansible_port=$port" >> hosts/ansible-hosts-up
    done
    echo "" >> hosts/ansible-hosts-up

    echo "[rke2-workers]" >> hosts/ansible-hosts-up
    for node in $New_Workers_Port; do
        ip=$(echo "$node" | awk -F':' '{print $1}')
        port=$(echo "$node" | awk -F':' '{print $2}')
        echo "$ip ansible_port=$port" >> hosts/ansible-hosts-up
    done
    echo "" >> hosts/ansible-hosts-up

    if [ -n "$Local_Port" ]; then
        echo "[local_host]" >> hosts/ansible-hosts-up
        echo "$Local_Address ansible_port=$Local_Port" >> hosts/ansible-hosts-up
    fi

    echo "生成的hosts-up文件:"
    cat hosts/ansible-hosts-up
    echo ""
}


delete_hosts(){
    echo "==== init ansible-hosts-del"
    echo "[del-nodes]" > hosts/ansible-hosts-del

    for node in $1; do
        if [[ -n "$node" ]]; then
            ip=$(echo "$node" | awk -F':' '{print $1}')
            port=$(echo "$node" | awk -F':' '{print $2}')
            echo "$ip ansible_port=$port" >> hosts/ansible-hosts-del
        fi
    done

    echo "" >> hosts/ansible-hosts-del
    echo "生成的hosts-del文件:"
    cat hosts/ansible-hosts-del
    echo ""
}

#------部署流程
if [[ ! -d hosts ]]; then
    mkdir -p hosts
fi

Joined_Nodes=""
Not_Joined_Nodes=""
#------判断$1位置变量是否为reset
if [[ "$1" == "reset" ]]; then
    for i in $All_Nodes; do
        if [[ "$i" != "$Local_Address" ]]; then
            if echo "$Get_All_Nodes" | grep -q -w "$i"; then
                Joined_Nodes="$Joined_Nodes $i"
                echo "✓ $i 已在集群中"
            else
                Not_Joined_Nodes="$Not_Joined_Nodes $i"
                echo "✗ $i 未在集群中"
            fi
        fi
    done
    echo ""
    echo "节点状态汇总:"
    echo "已在集群中的节点: $Joined_Nodes"
    echo "未在集群中的节点: $Not_Joined_Nodes"
    echo "当前控制节点: $Local_Address"
    echo ""
    while true; do
        read -p "WARNNING: 当前操作将清空上述所有节点，请确认输入后继续(y/n): " choice
        case "$choice" in
            y|Y) break ;;
            n|N) exit 0 ;;
            *) echo "输入无效，请重新输入(y/n)。" ;;
        esac
    done

    if [[ -n "$Joined_Nodes" ]]; then
        echo "====== 开始删除已加入集群的节点 ======"
        for i in $Joined_Nodes; do
            Node_name=$(ssh $SSH_OPTS -p "$Local_Port" "$Local_Address" kubectl get node -o wide | grep -w "$i" | awk '{print $1}')
            echo "== $i ($Node_name) 删除中......"
            ssh $SSH_OPTS -p "$Local_Port" "$Local_Address" kubectl delete node "$Node_name" && echo "== $Node_name ($i) - 节点已从集群中删除" || { echo "== $i - kubectl delete 执行失败，请检查！"; exit 1; }
            echo ""
        done
        echo "====== 节点删除完成 ======"
        echo ""
    fi

    echo "====== 生成卸载配置文件 ======"
    delete_hosts "$(echo "$All_Nodes_Port" | grep -v -w "$Local_Address")"

    echo "====== 开始卸载所有节点的rke2 ======"
    if echo "$All_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "== 卸载所有远程节点..."
        ansible-playbook -i hosts/ansible-hosts-del playbooks/playbook_delete_node.yaml
        echo "== 远程节点卸载完成"
    fi

    echo "====== 卸载本地master节点 ======"
    delete_hosts "${Local_Address}:${Local_Port}"
    ansible-playbook -i hosts/ansible-hosts-del playbooks/playbook_delete_node.yaml
    echo "== 本地节点卸载完成"

    echo ""
    echo "============================================="
    echo "集群重置完成！"
    echo ""

    if [[ -n "$Not_Joined_Nodes" ]]; then
        echo "注意：以下节点在cluster.yaml中配置但未加入集群，已被标记处理:"
        for node in $Not_Joined_Nodes; do
            echo "  - $node"
        done
        echo "  - $Local_Address"
        echo "这些节点上的rke2服务已被卸载（如果已安装）。"
    fi

    if [[ -n "$Joined_Nodes" ]]; then
        echo "已卸载的节点:"
        for node in $Joined_Nodes; do
            echo "  - $node"
        done
        echo "  - $Local_Address"
    fi

    echo ""
    echo "请检查所有节点上的rke2服务是否已完全卸载。"
    echo "如有需要，请手动清理相关残留文件和目录。"
    echo "============================================="
    echo ""

    exit 0
fi

#------判断Masters节点列表是否为空，决定是否初始化部署集群
if [[ -z "$Get_Masters" ]]; then
    if echo "$Master_List" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "[rke2-masters]"
        for i in $Master_List_Port; do
            echo "$i"
        done
    fi
    echo ""
    if echo "$Worker_List" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "[rke2-workers]"
        for i in $Worker_List_Port; do
            echo "$i"
        done
    fi
    echo ""
    echo "当前操作： 初始化部署k8s集群"

    while true; do
        read -p "请确认以上节点信息，输入后继续(y/n): " choice
        case "$choice" in
            y|Y) break ;;
            n|N) exit 0 ;;
            *) echo "输入无效，请重新输入(y/n)。" ;;
        esac
    done

    echo "==== 初始化hosts文件"
    init_hosts
    echo ""
    ansible-playbook -i hosts/ansible-hosts playbooks/playbook_install_rke2.yaml || exit 1
    ansible-playbook -i hosts/ansible-hosts playbooks/playbook_post_config.yaml -e "operation=init"
    echo "== 部署完成！=="
    printf "\n\n"

#------扩缩容
elif echo "$New_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "$Del_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
    # 一次性获取集群现有节点表（用于展示真实 nodeName，从 k8s 实时获取）
    Node_Table=$(ssh $SSH_OPTS -p "$Local_Port" "$Local_Address" kubectl get node -o wide 2>/dev/null)

    #------提示信息
    if echo "$New_Masters" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "$Del_Masters" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "[rke2-masters]"
        if echo "$Del_Masters" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
            for i in $Del_Masters_Port; do
                echo "$i - 删除"
            done
        fi
        if echo "$New_Masters" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
            for i in $New_Masters_Port; do
                echo "$i - 新增"
            done
        fi
    fi
    echo ""
    if echo "$New_Workers" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "$Del_Workers" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "[rke2-workers]"
        if echo "$Del_Workers" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
            for i in $Del_Workers_Port; do
                echo "$i - 删除"
            done
        fi
        if echo "$New_Workers" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
            for i in $New_Workers_Port; do
                echo "$i - 新增"
            done
        fi
    fi
    echo ""

    # 从 k8s 中查出待删除节点的真实 nodeName（实时，仅当有节点待删除时展示）
    if echo "$Del_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "k8s 节点信息(即将删除)："
        for i in $Del_Nodes; do
            name=$(echo "$Node_Table" | awk -v ip="$i" '$6 == ip {print $1; exit}')
            if [ -n "$name" ]; then
                echo "$name   $i"
            else
                echo "未找到   $i"
            fi
        done
        echo ""
    fi

    echo "当前操作： k8s节点扩缩容"

    while true; do
        read -p "请确认以上节点信息，输入后继续(y/n): " choice
        case "$choice" in
            y|Y) break ;;
            n|N) exit 0 ;;
            *) echo "输入无效，请重新输入(y/n)。" ;;
        esac
    done

    if echo "$Del_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "====== 删除节点 ======"
        delete_hosts "$Del_Nodes_Port"
        Deleted_Nodes_Info=""
        for i in $Del_Nodes; do
            Node_name=$(ssh $SSH_OPTS -p "$Local_Port" "$Local_Address" kubectl get node -o wide | grep -w "$i" | awk '{print $1}')
            echo "== $i 删除中......"
            echo "== kubectl delete node $Node_name ......"
            if ssh $SSH_OPTS -p "$Local_Port" "$Local_Address" kubectl delete node "$Node_name"; then
                echo "== ${Node_name}/$i - 节点已从集群中删除"
                Deleted_Nodes_Info="${Deleted_Nodes_Info}${Node_name}   ${i}"$'\n'
            else
                echo "== $i - kubectl delete 执行失败，请检查！"
                exit 1
            fi
            echo ""
        done
        echo "== 开始卸载rke2"
        ansible-playbook -i hosts/ansible-hosts-del playbooks/playbook_delete_node.yaml
        init_hosts

        # 展示本次成功删除的节点
        if [ -n "$Deleted_Nodes_Info" ]; then
            echo "本次成功删除节点："
            printf "%s" "$Deleted_Nodes_Info"
            echo ""
        fi

        echo "== 删除节点已完成！"
        echo ""
    fi

    if echo "$New_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "====== 新增节点 ======"
        init_hosts
        update_hosts
        ansible-playbook -i hosts/ansible-hosts-up playbooks/playbook_install_rke2.yaml && echo "== OK ==" || exit 1
        ansible-playbook -i hosts/ansible-hosts playbooks/playbook_post_config.yaml -e "operation=update"
        echo "==== 新增节点已完成！ ===="
        printf "\n\n"
    fi
else
    echo "当前集群已部署，未检测到需要新增/删除节点，请检查cluster.yaml 并确认您要执行的操作！"
fi
