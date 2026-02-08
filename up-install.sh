#!/bin/bash
# 由cluster.yaml中提取的IP列表
Master_List=$(sed -n '/^master:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F'[ :]' '{print $(NF-1)}')
Worker_List=$(sed -n '/^worker:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F'[ :]' '{print $(NF-1)}')
All_Nodes="$Master_List $Worker_List"
# 由cluster.yaml中提取的IP列表带端口号
Master_List_Port=$(sed -n '/^master:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F' ' '{print $NF}')
Worker_List_Port=$(sed -n '/^worker:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F' ' '{print $NF}')
All_Nodes_Port="$Master_List_Port $Worker_List_Port"
# 其他变量
CNI=$(cat cluster.yaml | egrep "^cni:" | awk -F' ' '{print $NF}')
Calico_Net=$(cat cluster.yaml | grep calico_net | awk -F' ' '{print $NF}')
master_ingress=$(cat cluster.yaml | egrep "^master_ingress:" | awk -F' ' '{print $NF}')
worker_ingress=$(cat cluster.yaml | egrep "^worker_ingress:" | awk -F' ' '{print $NF}')

# 先检查 kubectl 是否安装
if command -v kubectl &> /dev/null; then
    Get_Masters="$(kubectl get node -o wide 2> /dev/null | egrep "master|control-plane" | awk '{print $6}')"
    Get_Workers="$(kubectl get node -o wide 2> /dev/null | egrep -v "master|control-plane|STATUS" | awk '{print $6}')"
else
    Get_Masters=""
    Get_Workers=""
fi
Get_All_Nodes="$Get_Masters $Get_Workers"

# 计算新增的纯IP列表（未在集群中的节点）
New_Masters=$(echo "$Master_List" | tr ' ' '\n' | grep -Fxvf <(echo "$Get_Masters" | tr ' ' '\n') 2> /dev/null)
New_Workers=$(echo "$Worker_List" | tr ' ' '\n' | grep -Fxvf <(echo "$Get_Workers" | tr ' ' '\n') 2> /dev/null)
New_Nodes="$New_Masters $New_Workers"

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
New_Nodes_Port="$New_Masters_Port $New_Workers_Port"

# 计算需要删除的节点
Del_Masters=$(echo "$Get_Masters" | tr ' ' '\n' | grep -Fxvf <(echo "$Master_List" | tr ' ' '\n') 2> /dev/null)
Del_Workers=$(echo "$Get_Workers" | tr ' ' '\n' | grep -Fxvf <(echo "$Worker_List" | tr ' ' '\n') 2> /dev/null)
Del_Nodes="$Del_Masters $Del_Workers"

# 从hosts/ansible-hosts文件中获取删除节点的端口（关键修复）
# 只从[rke2]组中查找，避免重复
Del_Masters_Port=$(
    for ip in $Del_Masters; do
        # 从hosts/ansible-hosts文件中查找该IP的端口
        line=$(grep -E "^${ip}[[:space:]]" hosts/ansible-hosts | head -1)
        if [ -n "$line" ]; then
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
        if [ -n "$line" ]; then
            ip_part=$(echo "$line" | awk '{print $1}')
            port_part=$(echo "$line" | grep -o 'ansible_port=[0-9]*' | cut -d= -f2)
            echo "${ip_part}:${port_part}"
        fi
    done | tr '\n' ' ' | sed 's/ $//'
)

Del_Nodes_Port="$Del_Masters_Port $Del_Workers_Port"

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

# 更新新增节点的ansible hosts文件（逻辑和init_hosts一致）
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
    for node in $Del_Nodes_Port; do
        if [ -n "$node" ]; then
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
#------判断Masters节点列表是否为空，决定是否初始化部署集群
if [ -z "$Get_Masters" ]; then
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
    ansible-playbook -i hosts/ansible-hosts playbooks/playbook_install_rke2.yaml && source /etc/profile || exit 1
    
    #------给kube-proxy增加label
    echo "==== kube-proxy 添加 label k8s-app: kube-proxy ......"
    for i in $(kubectl get pod -n kube-system --show-labels | grep kube-proxy | grep -v k8s-app | awk '{print $1}'); do 
        kubectl label pod -n kube-system $i k8s-app=kube-proxy; 
    done  &&  echo "== ok =="  && echo "" || \
    echo "== label 添加失败，请检查！=="
    
    #------更新ingress配置
    if [[ ${master_ingress:-false} == "true" ]] || [[ ${worker_ingress:-false} == "true" ]]; then
        echo "==== 准备更新 ingress cm，先等待目标 CM 存在（超时 3 分钟） ===="
        
        # 1. 定义相关变量，方便后续修改和维护
        CM_NAME="rke2-ingress-nginx-controller"
        NAMESPACE="kube-system"
        TIMEOUT_SECONDS=180  # 3分钟 = 180秒
        CHECK_INTERVAL=5     # 每5秒检查一次CM是否存在
        END_TIME=$(( $(date +%s) + TIMEOUT_SECONDS ))  # 计算超时截止时间戳
        
        # 2. 循环检查 CM 是否存在，直到超时或 CM 创建成功
        while [[ $(date +%s) -lt $END_TIME ]]; do
            # kubectl get cm ，返回值 0 表示 CM 存在，非 0 表示不存在
            if kubectl get cm "$CM_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
                echo "==== 目标 CM $CM_NAME（命名空间 $NAMESPACE）已创建，开始执行更新 ===="
                break
            fi
            
            # CM 未存在，输出等待提示，然后睡眠指定间隔
            echo "==== 目标 CM $CM_NAME 尚未创建，继续等待（剩余超时时间：$(( END_TIME - $(date +%s) )) 秒） ===="
            sleep $CHECK_INTERVAL
        done
        
        # 3. 检查是否超时（循环结束后，若 CM 仍不存在则判定为超时）
        if ! kubectl get cm "$CM_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
            echo "==== 错误：等待 CM $CM_NAME 创建超时（超时时间 3 分钟） ===="
        fi
        
        # 4. 执行 CM 合并更新
        kubectl patch cm "$CM_NAME" -n "$NAMESPACE" \
          --type merge \
          -p '{"data": {
            "allow-snippet-annotations": "true",
            "proxy-body-size": "500m",
            "proxy-read-timeout": "1800",
            "proxy-send-timeout": "1800",
            "ssl-redirect": "false"
          }}' || echo "==== 错误：更新 CM $CM_NAME 失败 ===="
        
        # 5. 后续原有操作（删除 pod、等待就绪）
        kubectl delete pod -n kube-system -l app.kubernetes.io/instance=rke2-ingress-nginx --force
        echo "== 等待资源就绪( timeout: 5m )..."
        kubectl wait --for=condition=Ready pod -n kube-system -l app.kubernetes.io/instance=rke2-ingress-nginx --timeout=300s
        echo "== 完成 =="
        printf "\n\n"
    fi
    
    #------修改calico配置
    if [[ "$CNI" == "calico" ]]; then
        echo "==== 修改calico配置-使用网卡-$Calico_Net"
        echo "==== 等待资源就绪 installation default -n calico-system ......"
        while true; do
            kubectl get installation default -n calico-system &> /dev/null
            if [ $? -eq 0 ]; then
                kubectl patch installation default -n calico-system \
                    --type merge \
                    -p "{\"spec\":{\"calicoNetwork\":{\"nodeAddressAutodetectionV4\":{\"interface\":\"$Calico_Net\", \"firstFound\": null}}}}"
                if [ $? -eq 0 ]; then
                    echo "== calico 网卡已修改： $Calico_Net =="
                    echo "== 部署完成！=="
                    printf "\n\n"
                    kubectl get node
                    printf "\n\n"
                    echo "######---- 第一次执行kubectl 前 需要先 source /etc/profile ----######"
                    printf "\n"
                    exit 0
                else
                    echo "==== calico网卡修改失败，请检查！！ ===="
                    echo "== 部署完成！=="
                    printf "\n\n"
                    kubectl get node
                    echo "######---- 第一次执行kubectl 前 需要先 source /etc/profile ----######"
                    printf "\n"
                    exit 1
                fi
            else
                sleep 1
                continue
            fi
        done
    else
        echo "== 部署完成！=="
    fi
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
        delete_hosts
        for i in $Del_Nodes; do
            Node_name=$(kubectl get node -o wide | grep $i | awk '{print $1}')
            echo "== $i 删除中......"
            echo "== kubectl delete node $Node_name ......"
            kubectl delete node $Node_name && echo "== ${Node_name}/$i - 节点已从集群中删除" || { echo "== $i - kubectl delete 执行失败，请检查！"; exit 1; }
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
        echo "==== kube-proxy 添加 label k8s-app: kube-proxy ......"
        for i in $(kubectl get pod -n kube-system --show-labels | grep kube-proxy | grep -v k8s-app | awk '{print $1}'); do 
            kubectl label pod -n kube-system $i k8s-app=kube-proxy; 
        done  &&  echo "== ok =="  && echo "" || \
        echo "== label 添加失败，请检查！=="
        echo "==== 新增节点已完成！ ===="
        printf "\n\n"
    fi
else
    echo "当前集群已部署，未检测到需要新增/删除节点，请检查cluster.yaml 并确认您要执行的操作！"
fi