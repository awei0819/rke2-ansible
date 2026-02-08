#!/bin/bash
set -e  # 脚本执行出错时立即退出，避免后续无效操作

###########################################################################
# 1. 配置 RKE2 证书有效期环境变量（仅首次配置，已存在则跳过）
###########################################################################
ENV_FILE="/etc/default/rke2-server"
ENV_KEY="CATTLE_NEW_SIGNED_CERT_EXPIRATION_DAYS"
ENV_VALUE="36500"

if [ ! -f "$ENV_FILE" ]; then
    echo "=== 首次创建 RKE2 环境变量文件：$ENV_FILE ==="
    echo "$ENV_KEY=$ENV_VALUE" > "$ENV_FILE"
elif ! grep -q "^$ENV_KEY=$ENV_VALUE" "$ENV_FILE"; then
    echo "=== 更新 RKE2 环境变量：$ENV_KEY 为 $ENV_VALUE ==="
    # 先删除旧配置（若存在），再添加新配置
    sed -i "/^$ENV_KEY=/d" "$ENV_FILE"
    echo "$ENV_KEY=$ENV_VALUE" >> "$ENV_FILE"
else
    echo "=== RKE2 环境变量 $ENV_KEY=$ENV_VALUE 已存在，跳过 ==="
fi

###########################################################################
# 2. 创建证书目录（与 RKE2 数据目录对应，已存在则跳过）
###########################################################################
DATA_DIR="$(cat cluster.yaml | grep data_dir | awk -F' ' '{print $NF}')"
CERT_DIR="$DATA_DIR/server/tls"
ETCD_CERT_DIR="$CERT_DIR/etcd"

if [ ! -d "$ETCD_CERT_DIR" ]; then
    echo "=== 创建证书目录：$ETCD_CERT_DIR ==="
    mkdir -p "$ETCD_CERT_DIR"
    chmod -R 700 "$CERT_DIR"  # 目录权限：仅所有者可读写执行
    echo "=== 证书目录权限设置完成 ==="
else
    echo "=== 证书目录 $ETCD_CERT_DIR 已存在，跳过 ==="
fi

###########################################################################
# 3. 自签根 CA 证书（服务器端）：已存在则跳过
###########################################################################
# 服务器 CA 私钥/证书路径
SERVER_CA_KEY="$CERT_DIR/server-ca.key"
SERVER_CA_CSR="$CERT_DIR/server-ca.csr"
SERVER_CA_CRT="$CERT_DIR/server-ca.crt"
SERVER_CA_NOCHAIN="$CERT_DIR/server-ca.nochain.crt"

if [ ! -f "$SERVER_CA_CRT" ]; then
    echo "=== 生成服务器 CA 私钥（2048位）==="
    openssl genrsa -out "$SERVER_CA_KEY" 2048
    chmod 600 "$SERVER_CA_KEY"  # 私钥权限：仅所有者可读写

    echo "=== 生成服务器 CA 证书请求（CSR）==="
    openssl req -new -key "$SERVER_CA_KEY" \
        -out "$SERVER_CA_CSR" \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=RKE2/OU=CA/CN=RKE2 Server CA"

    echo "=== 自签服务器 CA 证书（有效期 100 年）==="
    openssl x509 -req -days 36500 \
        -in "$SERVER_CA_CSR" \
        -signkey "$SERVER_CA_KEY" \
        -out "$SERVER_CA_CRT"
    chmod 644 "$SERVER_CA_CRT"  # 证书权限：所有者可读写，其他用户可读

    echo "=== 生成服务器 CA 无链证书（RKE2 要求）==="
    cp "$SERVER_CA_CRT" "$SERVER_CA_NOCHAIN"
    chmod 644 "$SERVER_CA_NOCHAIN"
    echo "=== 服务器 CA 证书生成完成 ==="
else
    echo "=== 服务器 CA 证书 $SERVER_CA_CRT 已存在，跳过 ==="
fi

###########################################################################
# 4. 自签客户端 CA 证书：已存在则跳过
###########################################################################
# 客户端 CA 私钥/证书路径
CLIENT_CA_KEY="$CERT_DIR/client-ca.key"
CLIENT_CA_CSR="$CERT_DIR/client-ca.csr"
CLIENT_CA_CRT="$CERT_DIR/client-ca.crt"
CLIENT_CA_NOCHAIN="$CERT_DIR/client-ca.nochain.crt"

if [ ! -f "$CLIENT_CA_CRT" ]; then
    echo "=== 生成客户端 CA 私钥（2048位）==="
    openssl genrsa -out "$CLIENT_CA_KEY" 2048
    chmod 600 "$CLIENT_CA_KEY"

    echo "=== 生成客户端 CA 证书请求（CSR）==="
    openssl req -new -key "$CLIENT_CA_KEY" \
        -out "$CLIENT_CA_CSR" \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=RKE2/OU=CA/CN=RKE2 Client CA"

    echo "=== 自签客户端 CA 证书（有效期 100 年）==="
    openssl x509 -req -days 36500 \
        -in "$CLIENT_CA_CSR" \
        -signkey "$CLIENT_CA_KEY" \
        -out "$CLIENT_CA_CRT"
    chmod 644 "$CLIENT_CA_CRT"

    echo "=== 生成客户端 CA 无链证书（RKE2 要求）==="
    cp "$CLIENT_CA_CRT" "$CLIENT_CA_NOCHAIN"
    chmod 644 "$CLIENT_CA_NOCHAIN"
    echo "=== 客户端 CA 证书生成完成 ==="
else
    echo "=== 客户端 CA 证书 $CLIENT_CA_CRT 已存在，跳过 ==="
fi

###########################################################################
# 5. 自签 etcd 相关 CA 证书：已存在则跳过
###########################################################################
# 5.1 etcd 服务器 CA
ETCD_SERVER_KEY="$ETCD_CERT_DIR/server-ca.key"
ETCD_SERVER_CSR="$ETCD_CERT_DIR/server-ca.csr"
ETCD_SERVER_CRT="$ETCD_CERT_DIR/server-ca.crt"

if [ ! -f "$ETCD_SERVER_CRT" ]; then
    echo "=== 生成 etcd 服务器 CA 私钥（2048位）==="
    openssl genrsa -out "$ETCD_SERVER_KEY" 2048
    chmod 600 "$ETCD_SERVER_KEY"

    echo "=== 生成 etcd 服务器 CA 证书请求（CSR）==="
    openssl req -new -key "$ETCD_SERVER_KEY" \
        -out "$ETCD_SERVER_CSR" \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=RKE2/OU=etcd/CN=etcd Server CA"

    echo "=== 自签 etcd 服务器 CA 证书（有效期 100 年）==="
    openssl x509 -req -days 36500 \
        -in "$ETCD_SERVER_CSR" \
        -signkey "$ETCD_SERVER_KEY" \
        -out "$ETCD_SERVER_CRT"
    chmod 644 "$ETCD_SERVER_CRT"
    echo "=== etcd 服务器 CA 证书生成完成 ==="
else
    echo "=== etcd 服务器 CA 证书 $ETCD_SERVER_CRT 已存在，跳过 ==="
fi

# 5.2 etcd 节点间通信 CA
ETCD_PEER_KEY="$ETCD_CERT_DIR/peer-ca.key"
ETCD_PEER_CSR="$ETCD_CERT_DIR/peer-ca.csr"
ETCD_PEER_CRT="$ETCD_CERT_DIR/peer-ca.crt"

if [ ! -f "$ETCD_PEER_CRT" ]; then
    echo "=== 生成 etcd 节点通信 CA 私钥（2048位）==="
    openssl genrsa -out "$ETCD_PEER_KEY" 2048
    chmod 600 "$ETCD_PEER_KEY"

    echo "=== 生成 etcd 节点通信 CA 证书请求（CSR）==="
    openssl req -new -key "$ETCD_PEER_KEY" \
        -out "$ETCD_PEER_CSR" \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=RKE2/OU=etcd/CN=etcd Peer CA"

    echo "=== 自签 etcd 节点通信 CA 证书（有效期 100 年）==="
    openssl x509 -req -days 36500 \
        -in "$ETCD_PEER_CSR" \
        -signkey "$ETCD_PEER_KEY" \
        -out "$ETCD_PEER_CRT"
    chmod 644 "$ETCD_PEER_CRT"
    echo "=== etcd 节点通信 CA 证书生成完成 ==="
else
    echo "=== etcd 节点通信 CA 证书 $ETCD_PEER_CRT 已存在，跳过 ==="
fi

###########################################################################
# 6. 生成 request-header CA 证书：已存在则跳过
###########################################################################
REQ_HEADER_KEY="$CERT_DIR/request-header-ca.key"
REQ_HEADER_CSR="$CERT_DIR/request-header-ca.csr"
REQ_HEADER_CRT="$CERT_DIR/request-header-ca.crt"

if [ ! -f "$REQ_HEADER_CRT" ]; then
    echo "=== 生成 request-header CA 私钥（2048位）==="
    openssl genrsa -out "$REQ_HEADER_KEY" 2048

    echo "=== 生成 request-header CA 证书请求（CSR）==="
    openssl req -new -key "$REQ_HEADER_KEY" \
        -out "$REQ_HEADER_CSR" \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=RKE2/OU=CA/CN=RKE2 Request-Header CA"

    echo "=== 自签 request-header CA 证书（有效期 100 年）==="
    openssl x509 -req -days 36500 \
        -in "$REQ_HEADER_CSR" \
        -signkey "$REQ_HEADER_KEY" \
        -out "$REQ_HEADER_CRT"

    echo "=== 设置 request-header CA 权限（私钥 600，证书 644）==="
    chmod 600 "$REQ_HEADER_KEY"
    chmod 644 "$REQ_HEADER_CRT"
    echo "=== request-header CA 证书生成完成 ==="
else
    echo "=== request-header CA 证书 $REQ_HEADER_CRT 已存在，跳过 ==="
fi

###########################################################################
# 最终验证：检查关键证书是否齐全
###########################################################################
echo -e "\n=== 关键证书文件检查 ==="
KEY_FILES=("$SERVER_CA_KEY" "$CLIENT_CA_KEY" "$ETCD_SERVER_KEY" "$ETCD_PEER_KEY" "$REQ_HEADER_KEY")
CRT_FILES=("$SERVER_CA_CRT" "$CLIENT_CA_CRT" "$ETCD_SERVER_CRT" "$ETCD_PEER_CRT" "$REQ_HEADER_CRT")

all_exists=true
for file in "${KEY_FILES[@]}" "${CRT_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ 缺失关键文件：$file"
        all_exists=false
    else
        echo "✅ 存在：$file"
    fi
done

if $all_exists; then
    echo -e "\n=== 所有证书生成/检查完成！可继续部署 RKE2 集群 ==="
else
    echo -e "\n❌ 部分关键文件缺失，请检查脚本执行日志或重新运行脚本！"
    exit 1
fi

for cert in $(find "$CERT_DIR" -name "*.crt"); do   echo -e "\n=== 证书文件：$cert ===";   openssl x509 -in $cert -noout -dates; done


