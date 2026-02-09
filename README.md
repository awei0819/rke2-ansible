# 目录文件说明

```
cluster.yaml            # 核心配置文件，通过此文件来自动生成rke2的配置文件/etc/rancher/rke2/config.yaml
hosts/                  # 存放ansible-hosts文件（执行安装脚本自动生成）
playbooks/              # 存放playbook文件（安装和卸载）
README.txt              # 说明文档
rke2-artifacts.tgz      # rke2安装包，及calico镜像
up-install.sh           # 安装脚本
```

# 使用说明 #

```
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


对rke2不熟悉，可参考最下方 手动部署流程
本脚本，整合了离线安装包、镜像、自签证书、以及一些优化配置、简化操作流程、部署不踩坑、多版本多架构可复用
```


# rke2-artifacts.tgz 说明 #

```
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
```



# 数据目录说明 #

以全局数据目录定义: /data/rke2 为例

```
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

# 手动部署

RKE2 部署K8S v1.34.2+rke2r1(Ubuntu22.04)离线安装



## 1.主机配置列表

| 主机名      | [K8s](https://zhida.zhihu.com/search?content_id=267222685&content_type=Article&match_order=1&q=K8s&zd_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ6aGlkYV9zZXJ2ZXIiLCJleHAiOjE3NzA1Njg3NjEsInEiOiJLOHMiLCJ6aGlkYV9zb3VyY2UiOiJlbnRpdHkiLCJjb250ZW50X2lkIjoyNjcyMjI2ODUsImNvbnRlbnRfdHlwZSI6IkFydGljbGUiLCJtYXRjaF9vcmRlciI6MSwiemRfdG9rZW4iOm51bGx9.abj4sLPGcM2lDOIGzDEgE4l3eXwTqxKIk4fAMlhXdlQ&zhida_source=entity)节点类型 | ip地址        | 系统版本           |
| ----------- | ------------------------------------------------------------ | ------------- | ------------------ |
| k8s-master1 | Master                                                       | 192.168.80.31 | Ubuntu 22.04.5 LTS |
| k8s-master2 | Master                                                       | 192.168.80.32 | Ubuntu 22.04.5 LTS |
| k8s-master3 | Master                                                       | 192.168.80.33 | Ubuntu 22.04.5 LTS |
| k8s-worker1 | Slave                                                        | 192.168.80.34 | Ubuntu 22.04.5 LTS |

## 2. 配置hosts(所有主机)

```text
root@k8s-master1:~# vi /etc/hosts
192.168.80.31 k8s-master1
192.168.80.32 k8s-master2
192.168.80.33 k8s-master3
192.168.80.34 k8s-worker1
```

## 3.内核转发及网桥过滤(所有主机)

```text
# 添加系统启动时自动加载的内核模块
root@k8s-master1:~# vi /etc/modules-load.d/k8s.conf
overlay
br_netfilter
root@k8s-master1:~# modprobe overlay
root@k8s-master1:~# modprobe br_netfilter
# 立即加载模块
root@k8s-master1:~# lsmod | grep -E 'overlay|br_netfilter'
br_netfilter           32768  0
bridge                311296  1 br_netfilter
overlay               151552  0
# 开启桥接流量通过 iptables 和 ip6tables 过滤，启用 IPv4 数据包转发。
root@k8s-master1:~# vi /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
# 加载内核参数
sysctl --system


#####################-linux内核参数调优(第二种参数优化方式)-#####################
root@k8s-master1:~# cat > /etc/sysctl.d/k8s.conf << EOF
#开启网桥模式【重要】
net.bridge.bridge-nf-call-iptables=1
#开启网桥模式【重要】
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
# 禁止使用 swap 空间，只有当系统 OOM 时才允许使用它
vm.swappiness=0
# 不检查物理内存是否够用
vm.overcommit_memory=1
# 开启 OOM
vm.panic_on_oom=0
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
#关闭ipv6【重要】
# net.ipv6.conf.all.disable_ipv6=1
# net.netfilter.nf_conntrack_max=2310720

# 下面的内核参数可以解决ipvs模式下长连接空闲超时的问题
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.tcp_keepalive_time = 600
EOF
```

## 4.安装[ipset](https://zhida.zhihu.com/search?content_id=267222685&content_type=Article&match_order=1&q=ipset&zd_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ6aGlkYV9zZXJ2ZXIiLCJleHAiOjE3NzA1Njg3NjEsInEiOiJpcHNldCIsInpoaWRhX3NvdXJjZSI6ImVudGl0eSIsImNvbnRlbnRfaWQiOjI2NzIyMjY4NSwiY29udGVudF90eXBlIjoiQXJ0aWNsZSIsIm1hdGNoX29yZGVyIjoxLCJ6ZF90b2tlbiI6bnVsbH0.H1r2TAOds8DstHd__UZ3XtEzGcde4EwOOKDjqhN7AsU&zhida_source=entity)与[ipvsadm](https://zhida.zhihu.com/search?content_id=267222685&content_type=Article&match_order=1&q=ipvsadm&zd_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ6aGlkYV9zZXJ2ZXIiLCJleHAiOjE3NzA1Njg3NjEsInEiOiJpcHZzYWRtIiwiemhpZGFfc291cmNlIjoiZW50aXR5IiwiY29udGVudF9pZCI6MjY3MjIyNjg1LCJjb250ZW50X3R5cGUiOiJBcnRpY2xlIiwibWF0Y2hfb3JkZXIiOjEsInpkX3Rva2VuIjpudWxsfQ.-dPqMcfzfDKL2H37CRlWlmxT5zfiwk268dyjqJ8J7vg&zhida_source=entity)(所有主机)

```text
# 安装ipset及ipvsadm
root@k8s-master1:~# apt install -y ipset ipvsadm
# 配置ipvsadm模块加载
root@k8s-master1:~# cat << EOF | sudo tee /etc/modules-load.d/ipvs.conf
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF
# 立即加载ipvs模块
root@k8s-master1:~# modprobe --  ip_vs
root@k8s-master1:~# modprobe -- ip_vs_rr
root@k8s-master1:~# modprobe -- ip_vs_wrr
root@k8s-master1:~# modprobe -- ip_vs_sh
root@k8s-master1:~# modprobe -- nf_conntrack
# 查看ipvs模块是否加载
lsmod | grep ip_vs
```

## 5.时间同步(所有主机)

```text
root@k8s-master1:~# timedatectl set-timezone Asia/Shanghai
root@k8s-master1:~# apt install ntpdate -y
root@k8s-master1:~# ntpdate time1.aliyun.com
root@k8s-master1:~# crontab -e
0 0 * * * ntpdate time1.aliyun.com
```

## 6.禁用swap分区(所有主机)

```text
root@k8s-master1:~# swapoff -a && sudo sed -i '/swap/s/^/#/' /etc/fstab
```

## 7.禁用linux的透明大页、标准大页(未验证)

```text
root@k8s-master1:~# echo never > /sys/kernel/mm/transparent_hugepage/defrag
root@k8s-master1:~# echo never > /sys/kernel/mm/transparent_hugepage/enabled
root@k8s-master1:~# echo 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'  >> /etc/rc.local
root@k8s-master1:~# echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'  >> /etc/rc.local
root@k8s-master1:~# chmod +x /etc/rc.d/rc.local
```

## 8.文件数设置(所有主机)

```text
root@k8s-master1:~# ulimit -SHn 65535
root@k8s-master1:~# cat >> /etc/security/limits.conf <<EOF
* soft nofile 655360
* hard nofile 131072
* soft nproc 655350
* hard nproc 655350
* seft memlock unlimited
* hard memlock unlimitedd
EOF
```

## 9.[RKE2](https://zhida.zhihu.com/search?content_id=267222685&content_type=Article&match_order=1&q=RKE2&zd_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ6aGlkYV9zZXJ2ZXIiLCJleHAiOjE3NzA1Njg3NjEsInEiOiJSS0UyIiwiemhpZGFfc291cmNlIjoiZW50aXR5IiwiY29udGVudF9pZCI6MjY3MjIyNjg1LCJjb250ZW50X3R5cGUiOiJBcnRpY2xlIiwibWF0Y2hfb3JkZXIiOjEsInpkX3Rva2VuIjpudWxsfQ.Ct0gGbg019OIAbMJHu0aVZ6q796lWt9jEx3B-rIkO2w&zhida_source=entity) 安装与配置

### 9.1 第一台管理节点配置

### 9.1.1 下载离线安装文件(最好提前下载，有些东西可能无法从github拉取)

```text
# 创建文件夹下载离线文件
mkdir -pv /data/rke2-artifacts

# 创建rke2的image文件用来存储离线镜像
mkdir -pv /data/rke2/agent/images

# 下载v1.34.2版本(根据需要)
cd /data/rke2-artifacts

wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/rke2-images.linux-amd64.tar.zst
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/rke2.linux-amd64.tar.gz
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/sha256sum-amd64.txt


# 下载v1.29.15版本(根据需要)
cd /data/rke2-artifacts
wget https://github.com/rancher/rke2/releases/download/v1.29.15%2Brke2r1/rke2-images.linux-amd64.tar.zst
wget https://github.com/rancher/rke2/releases/download/v1.29.15%2Brke2r1/rke2.linux-amd64.tar.gz
wget https://github.com/rancher/rke2/releases/download/v1.29.15%2Brke2r1/sha256sum-amd64.txt


# 将离线镜像拷贝到指定文件夹
cp rke2-images.linux-amd64.tar.zst /data/rke2/agent/images


# 需要注意的是，calico的镜像官方是没有提供的，rke2-images.linux-amd64.tar.zst 里面不包含calico相关镜像
# 需要自己准备，可以先安装，看需要的镜像版本都是啥，这里我直接写好了（仅限k8s1.34.2）
# 镜像打包好，直接放到/data/rke2/agent/images 下即可，安装时会自动导入该目录下的镜像包
cd /data/rke2/agent/images
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
```

### 9.1.2 配置 RKE2 配置文件

配置文件详解，参考：[Server 配置参考 | Rancher文档](https://docs.rancher.cn/docs/rke2/install/install_options/server_config/)

```text
mkdir -p /etc/rancher/rke2
vim /etc/rancher/rke2/config.yaml

# config文件属性
write-kubeconfig-mode: "0600"

# 在server TLS证书上添加额外的主机名或IPv4/IPv6地址作为备用名称
# 如果使用负载均衡器（VIP）访问 API，可以添加上VIP地址
# 当前节点信息，ip、hostname
tls-san:
  - 192.168.80.31
  - k8s-master1

# 当前节点主机名
node-name: k8s-master1

# 指定网络插件
cni: calico

# 全局数据目录
data-dir: /data/rke2

# etcd备份保留个数，默认为5，每12小时备份一次
etcd-snapshot-retention: 10

# etcd-metrics监听地址
etcd-arg:
  - "--listen-metrics-urls=http://0.0.0.0:2381"

# kube-proxy-metrics监听地址
kube-proxy-arg:
  - "--metrics-bind-address=0.0.0.0:10249"

# kube-controller-manager 监听地址
kube-controller-manager-arg:
  - "--bind-address=0.0.0.0"

# kube-scheduler 监听地址
kube-scheduler-arg:
  - "--bind-address=0.0.0.0"

# 仓库配置
private-registry: "/etc/rancher/rke2/registries.yaml"



# 关闭ingress,默认为开启，无需配置，worker节点不需要，可以配置disable
# disable: rke2-ingress-nginx
```

### 9.1.3 配置使用私服仓库(可选,这里配置的是容器私服不是rke2需要镜像)

```text
cat > /etc/rancher/rke2/registries.yaml <<EOF
# 镜像代理配置
mirrors:
  docker.io:
    endpoint:
      - "https://registry.example.com"
  quay.io:
    endpoint:
      - "https://quay.example.com"
  www.aaa.com:  # 仓库名
    endpoint:
      - "http://reg.jthh.icloud.sinopec.com"  # 仓库地址

# 私有仓库认证配置
configs:
  "reg.jthh.icloud.sinopec.com":
    auth:
      username: admin
      password: 12345
    tls:
      insecure_skip_verify: true  # 跳过TLS证书验证
EOF



说明：
- mirrors 字段说明  
  表示当访问镜像时，会把 docker.io 重定向到国内的镜像网站 https://docker.mirrors.ustc.edu.cn
- configs 字段说明
  该段配置表示有镜像仓库，企业自己搭建的 harbor 仓库，如果没有私有仓库，则 configs 段配置可以省略。
- www.kubemsb.com 填写镜像仓库的地址。
- auth 块下的 username 和 password 填写仓库的登录账号密码。
如果镜像仓库访问时使用 https（使用了 tls），则需要填写 tls 的信息，如不验证 CA 证书，则 tls 下需要填写 insecure_skip_verify: true。如果需要验证，则需要填写 cert_file、key_file 和 ca_file 这三个参数。
```

### 9.1.4 安装Server端

```text
# 下载安装脚本并授权(官网 脚本curl -sfL https://get.rke2.io)
cd /data/rke2-artifacts
wget --no-check-certificate https://rancher-mirror.rancher.cn/rke2/install.sh
chmod +x install.sh 

# 指定版本国内源-主节点指定安装版本(使用线上脚本安装)(看需求，网络不好时使用)
curl -sfL https://rancher-mirror.rancher.cn/rke2/install.sh

# 安装
export INSTALL_RKE2_ARTIFACT_PATH=/data/rke2-artifacts
export INSTALL_RKE2_TYPE=server
export INSTALL_RKE2_ARCH=amd64
bash install.sh

输出：
[INFO]  staging local checksums from /data/rke2-artifacts/sha256sum-amd64.txt
[INFO]  staging zst airgap image tarball from /data/rke2-artifacts/rke2-images.linux-amd64.tar.zst
[INFO]  staging tarball from /data/rke2-artifacts/rke2.linux-amd64.tar.gz
[INFO]  verifying airgap tarball
[INFO]  installing airgap tarball to /var/lib/rancher/rke2/agent/images
[INFO]  verifying tarball
[INFO]  unpacking tarball file to /usr/local


# 查找 RKE2 安装位置：
root@k8s-master1:~# find / -name rke2
/etc/rancher/rke2
/usr/local/bin/rke2
/usr/local/share/rke2
/var/lib/rancher/rke2
/data/rke2
```

### 9.1.5 启动rke2Server开始初始化

```text
# 执行时间会比较久
systemctl enable rke2-server.service
systemctl start rke2-server.service

# 如果想查看初始化过程、状态、可以使用下面命令、报错连接不上etcd正常，多等一会就好了
journalctl -u rke2-server -f


# 查看安装生成的 token (其他master加入集群，和agent加入集群 需要)
root@k8s-master1:/data/rke2-artifacts# cat /data/rke2/server/node-token
输出：
K100f789c969f59f4377fedab6acdf4c28c3dd91716e06202616281e92041064c4f::server:bf8b4fc7486f62ab0f1fb58e38369380


# 查看集群信息(kubeconfig)
root@k8s-master1:/data/rke2-artifacts# cat /etc/rancher/rke2/rke2.yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: |
      LS0tLS1CRUdJTiBDRVJUSU...（省略的内容表示证书数据）
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
```

### 10.1.6 配置[kubectl](https://zhida.zhihu.com/search?content_id=267222685&content_type=Article&match_order=1&q=kubectl&zd_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ6aGlkYV9zZXJ2ZXIiLCJleHAiOjE3NzA1Njg3NjEsInEiOiJrdWJlY3RsIiwiemhpZGFfc291cmNlIjoiZW50aXR5IiwiY29udGVudF9pZCI6MjY3MjIyNjg1LCJjb250ZW50X3R5cGUiOiJBcnRpY2xlIiwibWF0Y2hfb3JkZXIiOjEsInpkX3Rva2VuIjpudWxsfQ.Jbu71tp-tFn-tdox0XBUdybgSb0y9cI-opKmLKBcHTU&zhida_source=entity)命令

```text
# 在安装完成后 kubectl 等二进制命令文件都在一个目录当中需要添加环境变量来使系统能够正常调用
root@k8s-master2:/data/rke2-artifacts# ls /data/rke2/bin
containerd  containerd-shim  containerd-shim-runc-v1  containerd-shim-runc-v2  crictl  ctr  kubectl  kubelet  runc

# 配置环境变量
cat > /etc/profile.d/rke2.sh << EOF
export PATH=$PATH:/data/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
EOF

# 配置ctr命令和crictl能够正常使用
echo 'alias ctr="/data/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io"' >> /etc/profile
echo 'export CRI_CONFIG_FILE=/data/rke2/agent/etc/crictl.yaml' >> /etc/profile

source /etc/profile


# 配置软连接，使其他插件可以管理k8s镜像，比如nerdctl，或docker可以启动，也依赖这个containerd.sock
# 永久生效，重启不丢失
echo 'L /run/containerd/containerd.sock - - - - /run/k3s/containerd/containerd.sock' >> /etc/tmpfiles.d/containerd-sock.conf

# 使配置立即生效
systemd-tmpfiles --create /etc/tmpfiles.d/containerd-sock.conf
ll /run/containerd/   # 查看软链是否生效


# 测试命令
root@k8s-master2:/data/rke2-artifacts# kubectl get nodes
NAME        STATUS   ROLES                AGE   VERSION
k8s-master1   Ready    control-plane,etcd   21m   v1.34.2+rke2r1



root@k8s-worker1:/data/rke2-artifacts# crictl images
IMAGE                                                                                   TAG                                                   IMAGE ID            SIZE
docker.io/rancher/hardened-addon-resizer                                                1.8.23-build20251016                                  682ffb21c0403       48.1MB
registry.cn-hangzhou.aliyuncs.com/rancher/hardened-addon-resizer                        1.8.23-build20251016                                  682ffb21c0403       48.1MB
docker.io/rancher/hardened-calico                                                       v3.30.3-build20251015                                 02dad26543033       686MB
.........
```

### 10.2 第二台管理节点加入

按master1的部署步骤操作，仅修改配置文件内容

```text
# 其他步骤都相同，配置文件稍作修改
mkdir -p /etc/rancher/rke2
vim /etc/rancher/rke2/config.yaml

# master1地址
server: https://192.168.80.31:9345

# 部署master1时获取的token
token: K100f789c969f59f4377fedab6acdf4c28c3dd91716e06202616281e92041064c4f::server:bf8b4fc7486f62ab0f1fb58e38369380

# 本节点主机名
node-name: k8s-master2

# 本节点IP
tls-san: 192.168.80.32

# 指定网络插件
cni: calico

# 全局数据目录
data-dir: /data/rke2

# kube-proxy-metrics监听地址
kube-proxy-arg:
  - "--metrics-bind-address=0.0.0.0:10249"

# 仓库配置
private-registry: "/etc/rancher/rke2/registries.yaml"
```

写入仓库配置

```
cat > /etc/rancher/rke2/registries.yaml <<EOF
# 镜像代理配置
mirrors:
  docker.io:
    endpoint:
      - "https://registry.example.com"
  quay.io:
    endpoint:
      - "https://quay.example.com"
  www.aaa.com:  # 仓库名
    endpoint:
      - "http://reg.jthh.icloud.sinopec.com"  # 仓库地址

# 私有仓库认证配置
configs:
  "reg.jthh.icloud.sinopec.com":
    auth:
      username: admin
      password: 12345
    tls:
      insecure_skip_verify: true  # 跳过TLS证书验证
EOF
```



### 10.3 第三台管理节点加入

按master1的部署步骤操作，仅修改配置文件内容

```text
# 其他步骤都相同，配置文件稍作修改
mkdir -p /etc/rancher/rke2
vim /etc/rancher/rke2/config.yaml

# master1地址
server: https://192.168.80.31:9345

# 部署master1时获取的token
token: K100f789c969f59f4377fedab6acdf4c28c3dd91716e06202616281e92041064c4f::server:bf8b4fc7486f62ab0f1fb58e38369380

# 本节点主机名
node-name: k8s-master3

# 本节点IP
tls-san: 192.168.80.33

# 指定网络插件
cni: calico

# 全局数据目录
data-dir: /data/rke2

# kube-proxy-metrics监听地址
kube-proxy-arg:
  - "--metrics-bind-address=0.0.0.0:10249"

# 仓库配置
private-registry: "/etc/rancher/rke2/registries.yaml"
```

```
cat > /etc/rancher/rke2/registries.yaml <<EOF
# 镜像代理配置
mirrors:
  docker.io:
    endpoint:
      - "https://registry.example.com"
  quay.io:
    endpoint:
      - "https://quay.example.com"
  www.aaa.com:  # 仓库名
    endpoint:
      - "http://reg.jthh.icloud.sinopec.com"  # 仓库地址

# 私有仓库认证配置
configs:
  "reg.jthh.icloud.sinopec.com":
    auth:
      username: admin
      password: 12345
    tls:
      insecure_skip_verify: true  # 跳过TLS证书验证
EOF
```



### 10.4 Work节点加入(所有从节点都可以这样操作)

```text
# 创建文件夹下载离线文件
mkdir -pv /data/rke2-artifacts

# 创建rke2的image文件用来存储离线镜像
mkdir -pv /data/rke2/agent/images

# 下载v1.34.2版本(根据需要)
cd /data/rke2-artifacts

wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/rke2-images.linux-amd64.tar.zst
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/rke2.linux-amd64.tar.gz
wget https://github.com/rancher/rke2/releases/download/v1.34.2%2Brke2r1/sha256sum-amd64.txt


# 将离线镜像拷贝到指定文件夹
cp rke2-images.linux-amd64.tar.zst /data/rke2/agent/images



mkdir -p /etc/rancher/rke2
vim /etc/rancher/rke2/config.yaml

# master1地址
server: https://192.168.80.31:9345

# 部署master1时获取的token
token: K100f789c969f59f4377fedab6acdf4c28c3dd91716e06202616281e92041064c4f::server:bf8b4fc7486f62ab0f1fb58e38369380

# 本节点主机名
node-name: k8s-worker1

# 全局数据目录
data-dir: /data/rke2

# kube-proxy-metrics监听地址
kube-proxy-arg:
  - "--metrics-bind-address=0.0.0.0:10249"
  
# 仓库配置
private-registry: "/etc/rancher/rke2/registries.yaml"
```

```
cat > /etc/rancher/rke2/registries.yaml <<EOF
# 镜像代理配置
mirrors:
  docker.io:
    endpoint:
      - "https://registry.example.com"
  quay.io:
    endpoint:
      - "https://quay.example.com"
  www.aaa.com:  # 仓库名
    endpoint:
      - "http://reg.jthh.icloud.sinopec.com"  # 仓库地址

# 私有仓库认证配置
configs:
  "reg.jthh.icloud.sinopec.com":
    auth:
      username: admin
      password: 12345
    tls:
      insecure_skip_verify: true  # 跳过TLS证书验证
EOF
```

安装agent

```
# 下载安装脚本并授权(官网 脚本curl -sfL https://get.rke2.io)
cd /data/rke2-artifacts
wget --no-check-certificate https://rancher-mirror.rancher.cn/rke2/install.sh
chmod +x install.sh 

# 安装
export INSTALL_RKE2_ARTIFACT_PATH=/data/rke2-artifacts
export INSTALL_RKE2_TYPE=agent
export INSTALL_RKE2_ARCH=amd64
bash install.sh
```

启动agent

```
# 执行时间会比较久
systemctl enable rke2-agent.service
systemctl start rke2-agent.service

# 如果想查看初始化过程、状态、可以使用下面命令、报错连接不上etcd正常，多等一会就好了
journalctl -u rke2-agent -f


# 配置环境变量
cat > /etc/profile.d/rke2.sh << EOF
export PATH=$PATH:/data/rke2/bin
EOF

# 配置ctr命令和crictl能够正常使用
echo 'alias ctr="/data/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io"' >> /etc/profile
echo 'export CRI_CONFIG_FILE=/data/rke2/agent/etc/crictl.yaml' >> /etc/profile

source /etc/profile


# 配置软连接，使其他插件可以管理k8s镜像，比如nerdctl，或docker可以启动，也依赖这个containerd.sock
# 永久生效，重启不丢失
echo 'L /run/containerd/containerd.sock - - - - /run/k3s/containerd/containerd.sock' >> /etc/tmpfiles.d/containerd-sock.conf

# 使配置立即生效
systemd-tmpfiles --create /etc/tmpfiles.d/containerd-sock.conf
ll /run/containerd/   # 查看软链是否生效

crictl images
```

## pod间通信

calico配置默认为主机上的第一个可用网卡，如果pod间通信有问题，则手动指定网卡

不管有没有问题，建议直接配上，避免日后出现问题

```
# 可以指定多个，逗号分隔
Calico_Net=eno*

kubectl patch installation default -n calico-system \
--type merge \
-p "{\"spec\":{\"calicoNetwork\":{\"nodeAddressAutodetectionV4\":{\"interface\":\"$Calico_Net\", \"firstFound\": null}}}}"
```

发布于 2025-12-04 21:43・北京
