## 简介

通过ansible一键完成多节点 RKE2 集群的部署与卸载，大幅降低 RKE2 K8S 集群的部署门槛和操作复杂度。

可快速完成生产级别K8S集群离线部署、简单、高效、多版本可复用。支持多架构混合部署。

RKE2相关信息参考rancher中文社区：https://docs.rancher.cn/docs/rke2/

## 文件说明 ##

```
/install-rke2-ansible   # 安装脚本目录
packages                # k8s镜像及rke2安装包存放目录，内有自动打包脚本
cluster.yaml            # 核心配置文件，通过此文件来自动渲染生成rke2的配置文件/etc/rancher/rke2/config.yaml
hosts/                  # 存放ansible-hosts文件（执行安装脚本自动生成）
playbooks/              # 存放playbook文件（安装、初始化、卸载）
ssh-copy.sh             # 免密脚本
up-install.sh           # 安装脚本
README.md               # 说明文档
```

## 前置要求

1、master1作为主控制节点、需安装docker服务。

2、各k8s节点需做好前置初始化工作，关闭防火墙、swap分区等、以满足k8s部署要求。

## 部署RKE2-K8S集群 

克隆仓库至数据目录

```
git clone https://github.com/awei0819/rke2-ansible.git  /data/install-rke2-ansible
```

打包rke2安装包（此处需要网络）

rke2版本参考：https://github.com/rancher/rke2/releases

```
cd /data/install-rke2-ansible/packages

# 执行打包脚本，必填参数 --arch 架构 --release k8s版本+rke2版本
bash download_rke2_artifacts.sh --arch amd64 --release v1.34.2+rke2r1

# 单架构只下载一个即可
bash download_rke2_artifacts.sh --arch arm64 --release v1.34.2+rke2r1

执行后，会在packages目录下生成安装包
```

启动ansible容器

使用ansible容器，避免ansible对宿主机python环境的依赖或版本冲突，满足版本需求的情况下，也可直接在宿主机执行后续操作（不使用ansible容器）

ansible 2.10.8

Python 3.10.12

低于以上版本可自行尝试，或直接使用ansible容器部署，特别是麒麟系统

```
# 拉取镜像
docker pull docker.io/awei666666/ansible:20260226-amd64
或
docker pull docker.io/awei666666/ansible:20260226-arm64

# 启动容器
cd /data/install-rke2-ansible

docker run -itd --name install-rke2-ansible \
  --restart always \
  -v $PWD:/install-rke2-ansible \
  -w /install-rke2-ansible \
docker.io/awei666666/ansible:20260226-amd64 /bin/bash
```

免密

```
# 进入容器
docker exec -it install-rke2-ansible bash

# 填写所有主机信息
vi /etc/ansible/hosts
[ssh-copy]
192.168.80.31
192.168.80.32
192.168.80.33
192.168.80.34
[ssh-copy:vars]
ansible_port=22
ansible_ssh_pass=your_password

# 如果端口和密码不一致
[ssh-copy]
# 格式：主机IP ansible_port=端口号 ansible_ssh_pass=密码
192.168.80.31 ansible_port=22 ansible_ssh_pass=password_31


# 获取容器内公钥
cat /root/.ssh/id_rsa.pub

# 替换内容
sed -i 's#^ssh_key.*#ssh_key="<上一步查到的公钥>"#1' ./ssh-copy.sh

# 执行免密脚本
ansible ssh-copy -m script -a "./ssh-copy.sh"
```

部署集群

```
#------------- 容器内操作 ------------
# 配置 cluster.yaml 文件中有填写说明
vi cluster.yaml

# 执行部署，等待k8s集群安装完毕
bash up-install.sh
```



## 操作说明

```
# 集群安装
# 配置好cluster.yaml 执行up脚本、等待集群安装完毕
# 可新开终端 journalctl -u rke2-server.service -f 查看日志，etcd有报错正常，等待即可
bash up-install.sh

# 节点扩缩容
# cluster.yaml中 增删节点信息，执行up脚本
bash up-install.sh

# 集群清理/卸载 cluster.yaml中记录的所有节点
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