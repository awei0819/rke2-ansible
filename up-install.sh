#!/bin/bash
rke2_data_dir=$(cat cluster.yaml | grep data_dir | awk -F' ' '{print $NF}')
# 由cluster.yaml中提取的IP列表
Master_List=$(sed -n '/^master:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F'[ :]' '{print $(NF-1)}')
Worker_List=$(sed -n '/^worker:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F'[ :]' '{print $(NF-1)}')
All_Nodes="
$Master_List
$Worker_List
"
# 由cluster.yaml中提取的IP列表带端口号
Master_List_Port=$(sed -n '/^master:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F' ' '{print $NF}')
Worker_List_Port=$(sed -n '/^worker:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F' ' '{print $NF}')

All_Nodes_Port="
$Master_List_Port
$Worker_List_Port
"
# 其他变量
CNI=$(cat cluster.yaml | egrep "^cni:" | awk -F' ' '{print $NF}')
Calico_Net=$(cat cluster.yaml | grep calico_net | awk -F' ' '{print $NF}')
master_ingress=$(cat cluster.yaml | egrep "^master_ingress:" | awk -F' ' '{print $NF}')
worker_ingress=$(cat cluster.yaml | egrep "^worker_ingress:" | awk -F' ' '{print $NF}')

Local_Address=$(cat cluster.yaml | grep local_address | awk -F' ' '{print $NF}')
Local_Port=$(cat cluster.yaml | grep ${Local_Address}: | awk -F ':' '{print $NF}')

Get_Masters="$(ssh $Local_Address -p $Local_Port kubectl get node -o wide 2> /dev/null | egrep "master|control-plane" | awk '{print $6}')"
Get_Workers="$(ssh $Local_Address -p $Local_Port kubectl get node -o wide 2> /dev/null | egrep -v "master|control-plane|STATUS" | awk '{print $6}')"
Get_All_Nodes="
$Get_Masters
$Get_Workers
"

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
    done | tr '\n' ' ' | sed 's/ $//'  # 转为空格分隔的字符串，去掉末尾空格
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
# 只从[rke2]组中查找，避免重复
Del_Masters_Port=$(
    for ip in $Del_Masters; do
        # 从hosts/ansible-hosts文件中查找该IP的端口
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
        # 从hosts/ansible-hosts文件中查找该IP的端口
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
    # 清空并创建hosts文件，写入[rke2]组（拆分IP:端口为IP ansible_port=端口）
    echo "[rke2]" > hosts/ansible-hosts
    for node in $All_Nodes_Port; do
        # 拆分IP和端口：IP=冒号前的部分，PORT=冒号后的部分
        ip=$(echo "$node" | awk -F':' '{print $1}')
        port=$(echo "$node" | awk -F':' '{print $2}')
        # 按Ansible标准格式写入（IP ansible_port=端口）
        echo "$ip ansible_port=$port" >> hosts/ansible-hosts
    done
    echo "" >> hosts/ansible-hosts

    # 写入[rke2-masters]组
    echo "[rke2-masters]" >> hosts/ansible-hosts
    for node in $Master_List_Port; do
        ip=$(echo "$node" | awk -F':' '{print $1}')
        port=$(echo "$node" | awk -F':' '{print $2}')
        echo "$ip ansible_port=$port" >> hosts/ansible-hosts
    done
    echo "" >> hosts/ansible-hosts

    # 写入[rke2-workers]组
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

    echo "生成的hosts-up文件:"
    cat hosts/ansible-hosts-up
    echo ""
}


delete_hosts(){
    echo "==== init ansible-hosts-del"
    echo "[del-nodes]" > hosts/ansible-hosts-del
    
    # 写入所有需要删除的节点（不区分master/worker）
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




#-------------------------------部署流程
if [[ ! -d hosts ]];then
    mkdir -p hosts
fi
#------判断$1位置变量是否为reset
if [[ $1 == "reset" ]]; then
    while true; do
        read -p "WARNNING: 当前操作将清空集群所有节点，请确认输入后继续(y/n): " choice
        case "$choice" in
            y|Y)
                break
                ;;
            n|N)
                exit 0
                ;;
            *)
                echo "输入无效，请重新输入(y/n)。"
                ;;
        esac
    done
    
    # 分离已加入集群的节点和未加入集群的节点
    Joined_Nodes=""   # 已加入集群的节点
    Not_Joined_Nodes=""  # 未加入集群的节点
    
    # 检查每个节点是否在集群中
    for i in $All_Nodes; do
        if [[ "$i" != "$Local_Address" ]];then
            if echo "$Get_All_Nodes" | grep -q "$i"; then
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
    echo "已在集群中的节点: $Local_Address $Joined_Nodes"
    echo "未在集群中的节点: $Not_Joined_Nodes"
    echo "当前控制节点: $Local_Address"
    echo ""
    
    # 删除已加入集群的节点
    if [[ -n "$Joined_Nodes" ]]; then
        echo "====== 开始删除已加入集群的节点 ======"
        for i in $Joined_Nodes; do
            Node_name=$(ssh $Local_Address -p $Local_Port kubectl get node -o wide | grep $i | awk '{print $1}')
            echo "== $i ($Node_name) 删除中......"
            ssh $Local_Address -p $Local_Port kubectl delete node $Node_name && echo "== $Node_name ($i) - 节点已从集群中删除" || { echo "== $i - kubectl delete 执行失败，请检查！"; exit 1; }
            echo ""
        done
        echo "====== 节点删除完成 ======"
        echo ""
    fi
    
    # 生成卸载用的hosts文件（包含所有节点，除了本地节点）
    echo "====== 生成卸载配置文件 ======"
    delete_hosts "$(echo "$All_Nodes_Port" | grep -v $Local_Address)"
    
    # 执行卸载rke2（卸载所有节点，包括未加入集群的）
    echo "====== 开始卸载所有节点的rke2 ======"
    if echo "$All_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "== 卸载所有远程节点..."
        ansible-playbook -i hosts/ansible-hosts-del playbooks/playbook_delete_node.yaml
        echo "== 远程节点卸载完成"
    fi
    
    # 卸载本地master节点
    echo "====== 卸载本地master节点 ======"
    delete_hosts "${Local_Address}:${Local_Port}"
    ansible-playbook -i hosts/ansible-hosts-del playbooks/playbook_delete_node.yaml
    echo "== 本地节点卸载完成"
    
    # 输出总结信息
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
    # 提示信息
    if echo "$Master_List" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "[rke2-masters]"
        for i in $Master_List_Port; do
            echo $i
        done
    fi
    echo ""
    if echo "$Worker_List" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "[rke2-workers]"
        for i in $Worker_List_Port; do
            echo $i
        done
    fi
    echo ""
    echo "当前操作： 初始化部署k8s集群"
    
    #------读取用户输入，根据输入操作
    while true; do
        read -p "请确认以上节点信息，输入后继续(y/n): " choice
        case "$choice" in
            y|Y)
                break
                ;;
            n|N)
                exit 0
                ;;
            *)
                echo "输入无效，请重新输入(y/n)。"
                ;;
        esac
    done

    #------初始化部署操作
	echo "==== 初始化hosts文件"
    init_hosts
	echo ""
    # 执行安装playbook
    ansible-playbook -i hosts/ansible-hosts playbooks/playbook_install_rke2.yaml || exit 1
    # 执行配置playbook（在local_address节点上执行kubectl操作）
    ansible-playbook -i hosts/ansible-hosts playbooks/playbook_post_config.yaml \
      -e "operation=init" \
      -e "kube_host=$Local_Address" \
      -e "master_ingress=$master_ingress" \
      -e "worker_ingress=$worker_ingress" \
      -e "cni=$CNI" \
      -e "calico_net=$Calico_Net"
    echo "== 部署完成！=="
    printf "\n\n"    

#------如果不是初始化部署集群，判断是否有需要新增或删除的节点IP，执行扩缩容操作
elif echo "$New_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "$Del_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
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
    echo "当前操作： k8s节点扩缩容"

    #------读取用户输入，根据输入操作
    while true; do
        read -p "请确认以上节点信息，输入后继续(y/n): " choice
        case "$choice" in
            y|Y)
                break
                ;;
            n|N)
                exit 0
                ;;
            *)
                echo "输入无效，请重新输入(y/n)。"
                ;;
        esac
    done

    #------删除节点
    if echo "$Del_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "====== 删除节点 ======"
        delete_hosts "$Del_Nodes_Port"
        for i in $Del_Nodes; do
            Node_name=$(ssh $Local_Address -p $Local_Port kubectl get node -o wide | grep $i | awk '{print $1}')
            echo "== $i 删除中......"
            echo "== kubectl delete node $Node_name ......"
            ssh $Local_Address -p $Local_Port kubectl delete node $Node_name && echo "== ${Node_name}/$i - 节点已从集群中删除" || { echo "== $i - kubectl delete 执行失败，请检查！"; exit 1; }
            echo ""
        done
        # 执行卸载rke2
        echo "== 开始卸载rke2"
        ansible-playbook -i hosts/ansible-hosts-del playbooks/playbook_delete_node.yaml
        init_hosts
        echo "== 删除节点已完成！"
        echo ""
    fi

    #------新增节点
    if echo "$New_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
        echo "====== 新增节点 ======"
        init_hosts
        update_hosts
        ansible-playbook -i hosts/ansible-hosts-up playbooks/playbook_install_rke2.yaml && echo "== OK ==" || exit 1
        
        # 执行配置playbook（在local_address节点上执行kubectl操作）
        ansible-playbook -i hosts/ansible-hosts playbooks/playbook_post_config.yaml \
            -e "operation=update" \
            -e "kube_host=$Local_Address"
        echo "==== 新增节点已完成！ ===="
        printf "\n\n"
    fi
else
    echo "当前集群已部署，未检测到需要新增/删除节点，请检查cluster.yaml 并确认您要执行的操作！"
fi
