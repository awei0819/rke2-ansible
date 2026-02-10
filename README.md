#### 目录文件说明 ##
/install-rke2-ansible
cluster.yaml            # 核心配置文件，通过此文件来自动渲染生成rke2的配置文件/etc/rancher/rke2/config.yaml
hosts/                  # 存放ansible-hosts文件（执行安装脚本自动生成）
playbooks/              # 存放playbook文件（安装和卸载）
README.md               # 说明文档
up-install.sh           # 安装脚本



## 使用说明 ##
前置要求：
k8s节点需做好前置初始化工作，满足k8s部署要求，可参考下方 手动部署部分

部署流程：

docker pull rke2-ansible:v1.34.2

# 配置拷贝，防止丢失
docker run -itd --name install-rke2-ansible rke2-ansible:v1.34.2 /bin/bash
docker cp install-rke2-ansible:/install-rke2-ansible  /data/
docker rm -f install-rke2-ansible

# 启动容器
docker run -itd --name install-rke2-ansible \
-v /data/install-rke2-ansible:/install-rke2-ansible \
rke2-ansible:v1.34.2 /bin/bash


# 获取容器公钥
docker exec -it install-rke2-ansible cat /root/.ssh/id_rsa.pub

# ssh_key替换为上一步获取的公钥  在所有节点执行（容器对所有节点免密）
ssh_key="ssh-rsa AAAAB3Ng0Heg630iGmhFBbjU= root@pm-wuhu0004"
mkdir -p /root/.ssh
echo "$ssh_key" >>/root/.ssh/authorized_keys


#------------- 容器内操作 ------------
# 进入容器执行部署操作
$ docker exec -it install-rke2-ansible bash
root@7544e5688809:/# cd install-rke2-ansible/

# 配置 cluster.yaml 
root@7544e5688809:/install-rke2-ansible# vi cluster.yaml

# 执行部署，等待安装完毕即可
bash up-install.sh



5、其他操作参考rancher中文社区：https://docs.rancher.cn/docs/rke2/


## 数据目录说明 ##
以全局数据目录定义: /data/rke2 为例

# containerd
数据：/data/rke2/agent/containerd
配置：/data/rke2/agent/etc

# kubelet
数据：/var/lib/kubelet
配置：/data/rke2/agent/etc

# etcd
数据：/data/rke2/server/db/etcd
备份：/data/rke2/server/db/snapshots

# 静态pod
配置：/data/rke2/agent/pod-manifests

# 集群证书
/data/rke2/server/tls