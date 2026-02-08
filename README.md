#### 目录文件说明 ##
ansible_install_pkg/    # ansible安装包和python编译包（3.10.12）
cluster.yaml            # 核心配置文件，通过此文件来自动生成rke2的配置文件/etc/rancher/rke2/config.yaml
create_tls.sh           # 自签证书脚本 100年
hosts/                  # 存放ansible-hosts文件（执行安装脚本自动生成）
playbooks/              # 存放playbook文件（安装和卸载）
README.txt              # 说明文档
rke2-artifacts.tgz      # rke2安装包，及calico镜像
up-install.sh           # 安装脚本



## 使用说明 ##
前置要求：
1、python版本: 3.10.12 
2、ansible版本: 2.10.8+
低于要求版本，可自行尝试是否有问题，安装包中已预置python和ansible的安装包
3、安装前需确保服务器环境满足k8s部署要求，做好初始化工作
4、需要以root用户执行

部署流程：
1、安装ansible，master1需要对所有机器免密
2、配置cluster.yaml
3、bash up-install.yaml
等待集群安装完毕即可
4、后续增减节点只需在cluster.yaml 中增加或删减ip，然后再次执行 bash up-install.yaml  即可完成节点扩缩容
5、其他操作参考rancher中文社区：https://docs.rancher.cn/docs/rke2/




## rke2-artifacts.tgz 说明 ##
内含rke2安装脚本、所需镜像及校验文件
安装其他版本，或arm64版本，可复用部署脚本，替换此包即可

打包流程(amd64为例)：

# 创建目录
mkdir rke2-artifacts && cd rke2-artifacts

# 安装集群必须的文件
# 版本，架构，可自己决定，只要最后的包名为 rke2-artifacts.tgz 即可
# arm64架构，需要将playbook中的amd64全文替换为arm64（amd支持任意版本）
# 这里的下载链接也替换为arm64
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/rke2-images.linux-amd64.tar.zst
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/rke2.linux-amd64.tar.gz
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/sha256sum-amd64.txt
wget --no-check-certificate https://rancher-mirror.rancher.cn/rke2/install.sh

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
