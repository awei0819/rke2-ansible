## 简介

通过docker容器（内置ansible及rke2安装包） 一键完成多节点 RKE2 集群的部署与卸载，大幅降低 RKE2 K8S 集群的部署门槛和操作复杂度。

可快速完成生产级别K8S集群离线部署、简单、高效、多版本可复用。支持多架构混合部署。

RKE2相关信息参考rancher中文社区：https://docs.rancher.cn/docs/rke2/

## 文件说明 ##

```
/install-rke2-ansible   # 安装脚本目录
packages                # k8s镜像及rke2安装包存放目录，内有自动打包脚本
cluster.yaml            # 核心配置文件，通过此文件来自动渲染生成rke2的配置文件/etc/rancher/rke2/config.yaml
hosts/                  # 存放ansible-hosts文件（执行安装脚本自动生成）
playbooks/              # 存放playbook文件（安装、初始化、卸载）
up-install.sh           # 安装脚本
README.md               # 说明文档
```

## 前置要求

1、master1作为主控制节点、需安装docker服务。

1、各k8s节点需做好前置初始化工作，关闭防火墙、swap分区等、以满足k8s部署要求。

## 使用ansible容器部署RKE2-K8S集群 v1.34.2

```
cd /data

git clone https://github.com/awei0819/rke2-ansible.git

cd install-rke2-ansible

# 拉取镜像
docker pull docker.io/awei666666/ansible:20260211

# 启动容器
docker run -itd --name install-rke2-ansible \
  --restart always \
  -v $PWD:/install-rke2-ansible \
  -w /install-rke2-ansible \
docker.io/awei666666/ansible:20260211 /bin/bash

# 获取容器内公钥
docker exec -it install-rke2-ansible cat /root/.ssh/id_rsa.pub

# 将ssh_key替换为上一步获取的公钥  在所有节点执行（该容器将对所有节点免密）
ssh_key="ssh-rsa AAAAB3Ng0Heg630iGmhFBbjU= root@pm-wuhu0004"
mkdir -p /root/.ssh
echo "$ssh_key" >>/root/.ssh/authorized_keys

#------------- 容器内操作 ------------
# 进入容器
docker exec -it install-rke2-ansible bash

cd /install-rke2-ansible

# 配置 cluster.yaml 文件中有填写说明
root@7544e5688809:/install-rke2-ansible# vi cluster.yaml

# 执行部署，等待安装完毕即可
bash up-install.sh
```

## 操作说明

```
# 集群安装
# 配置好cluster.yaml 执行up脚本、等待集群安装完毕
bash up-install.sh

# 节点扩缩容
# cluster.yaml中 增删节点信息，执行up脚本
bash up-install.sh

# 集群清理/卸载(cluster.yaml中的所有节点)
bash up-install.sh reset
```



## 数据目录说明 ##

```
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
```