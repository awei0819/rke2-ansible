## 简介

通过 docker 容器 封装好 ansible 及 RKE2 K8S 安装包、避免与宿主机环境冲突，启动容器后、仅需修改核心配置文件即可一键完成多节点 RKE2 集群的部署与卸载，大幅降低 RKE2 集群的部署门槛和操作复杂度。

可快速完成生产级别kubernetes集群离线部署、简单、高效、多版本可复用。

RKE2相关信息参考rancher中文社区：https://docs.rancher.cn/docs/rke2/

## 容器内文件说明 ##

```
/install-rke2-ansible   # 安装脚本目录
cluster.yaml            # 核心配置文件，通过此文件来自动渲染生成rke2的配置文件/etc/rancher/rke2/config.yaml
hosts/                  # 存放ansible-hosts文件（执行安装脚本自动生成）
playbooks/              # 存放playbook文件（安装和卸载）
README.md               # 说明文档
up-install.sh           # 安装脚本

/rke2-artifacts.tgz     # rke2安装包和k8s组件镜像
```

## 前置要求

1、控制节点 需安装docker服务。

1、各k8s节点需做好前置初始化工作，关闭防火墙、swap分区等、以满足k8s部署要求。

## 使用docker部署RKE2-K8S集群 v1.34.2

```
# 拉取镜像
docker pull awei666666/rke2-ansible:v1.34.2_amd64_260210

# 配置拷贝，防止丢失
docker run -itd --name install-rke2-ansible awei666666/rke2-ansible:v1.34.2_260210 /bin/bash
docker cp install-rke2-ansible:/install-rke2-ansible  /data/
docker rm -f install-rke2-ansible

# 启动容器
docker run -itd --name install-rke2-ansible \
--restart always \
-v /data/install-rke2-ansible:/install-rke2-ansible \
rke2-ansible:v1.34.2 /bin/bash

# 获取容器内公钥
docker exec -it install-rke2-ansible cat /root/.ssh/id_rsa.pub

# 将ssh_key替换为上一步获取的公钥  在所有节点执行（容器对所有节点免密）
ssh_key="ssh-rsa AAAAB3Ng0Heg630iGmhFBbjU= root@pm-wuhu0004"
mkdir -p /root/.ssh
echo "$ssh_key" >>/root/.ssh/authorized_keys


#------------- 容器内操作 ------------
# 进入容器执行部署操作
docker exec -it install-rke2-ansible bash
cd install-rke2-ansible/

# 配置 cluster.yaml 文件中有填写说明
root@7544e5688809:/install-rke2-ansible# vi cluster.yaml

# 执行部署，等待安装完毕即可
bash up-install.sh
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

## 打包 rke2-artifacts.tgz

下方文件 在[Releases · rancher/rke2](https://github.com/rancher/rke2/releases)均可下载

```
安装其他k8s版本，或arm64版本，可复用部署脚本，替换此包即可
打包流程(amd64为例)

# 创建目录
mkdir rke2-artifacts && cd rke2-artifacts

# 下载rke2安装文件
# 版本，架构，可自己决定，只要最后的包名为 rke2-artifacts.tgz 即可
# arm64架构，需要将playbook中的amd64全文替换为arm64（amd支持任意版本）
# 这里的下载链接也替换为arm64

wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/rke2-images.linux-amd64.tar.zst
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/rke2.linux-amd64.tar.gz
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/sha256sum-amd64.txt
wget --no-check-certificate https://rancher-mirror.rancher.cn/rke2/install.sh

# calico的镜像需单独下载，rke2预置镜像包中没有
mkdir calico && cd calico
docker pull docker.io/rancher/mirrored-calico-operator:v1.38.7
docker pull docker.io/rancher/mirrored-calico-node:v3.30.4
docker pull docker.io/rancher/mirrored-calico-pod2daemon-flexvol:v3.30.4
docker pull docker.io/rancher/mirrored-calico-cni:v3.30.4
docker pull docker.io/rancher/mirrored-calico-kube-controllers:v3.30.4
docker pull docker.io/rancher/mirrored-calico-typha:v3.30.4

docker save -o docker.io-rancher-mirrored-calico-operator_v1.38.7.tar docker.io/rancher/mirrored-calico-operator:v1.38.7
docker save -o docker.io-rancher-mirrored-calico-node:v3.30.4.tar docker.io/rancher/mirrored-calico-node:v3.30.4
docker save -o docker.io-rancher-mirrored-calico-pod2daemon-flexvol_v3.30.4.tar docker.io/rancher/mirrored-calico-pod2daemon-flexvol:v3.30.4
docker save -o docker.io-rancher-mirrored-calico-cni_v3.30.4.tar docker.io/rancher/mirrored-calico-cni:v3.30.4
docker save -o docker.io-rancher-mirrored-calico-kube-controllers_v3.30.4.tar docker.io/rancher/mirrored-calico-kube-controllers:v3.30.4
docker save -o docker.io-rancher-mirrored-calico-typha_v3.30.4.tar docker.io/rancher/mirrored-calico-typha:v3.30.4

$ ll rke2-artifacts/
total 808216
drwxr-xr-x 2 root root      4096 Feb  8 13:18 calico_images/
-rwxr-xr-x 1 root root     26276 Feb  8 12:02 install.sh*
-rw-r--r-- 1 root root 787726342 Nov 21 04:30 rke2-images.linux-amd64.tar.zst
-rw-r--r-- 1 root root  39839824 Nov 21 04:30 rke2.linux-amd64.tar.gz
-rw-r--r-- 1 root root      4252 Nov 21 04:30 sha256sum-amd64.txt

# 打包
tar czvf rke2-artifacts.tgz rke2-artifacts/
```

