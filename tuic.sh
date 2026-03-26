#!/usr/bin/env bash

set -e

# ===== 基础变量 =====
PORT=${PORT:-10443}
UUID=$(cat /proc/sys/kernel/random/uuid)
PASSWORD=$(openssl rand -base64 16)
INSTALL_DIR="/etc/tuic"
BIN_PATH="/usr/local/bin/tuic-server"
SERVICE_NAME="tuic"

echo "==== TUIC 一键安装 ===="

# ===== 检测系统 =====
if [ -f /etc/alpine-release ]; then
    OS="alpine"
elif [ -f /etc/debian_version ]; then
    OS="debian"
else
    echo "❌ 不支持的系统"
    exit 1
fi

echo "系统: $OS"

# ===== 安装依赖 =====
if [ "$OS" = "alpine" ]; then
    apk add --no-cache curl openssl
else
    apt update
    apt install -y curl openssl
fi

# ===== 获取最新版本 =====
VERSION=$(curl -s https://api.github.com/repos/Itsusinn/tuic/releases/latest | grep tag_name | cut -d '"' -f 4)

echo "最新版本: $VERSION"

# ===== 下载 =====
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    FILE="tuic-server-linux-amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    FILE="tuic-server-linux-arm64"
else
    echo "❌ 不支持架构"
    exit 1
fi

curl -L -o $BIN_PATH https://github.com/Itsusinn/tuic/releases/download/${VERSION}/${FILE}
chmod +x $BIN_PATH

# ===== 创建目录 =====
mkdir -p $INSTALL_DIR

# ===== 生成证书 =====
openssl req -x509 -newkey rsa:2048 \
-keyout $INSTALL_DIR/key.pem \
-out $INSTALL_DIR/cert.pem \
-days 3650 -nodes \
-subj "/CN=tuic"

# ===== 写配置 =====
cat > $INSTALL_DIR/config.json <<EOF
{
  "server": "[::]:${PORT}",
  "users": {
    "${UUID}": "${PASSWORD}"
  },
  "certificate": "$INSTALL_DIR/cert.pem",
  "private_key": "$INSTALL_DIR/key.pem",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_ipv6": true
}
EOF

# ===== systemd =====
if command -v systemctl >/dev/null 2>&1; then
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=TUIC Server
After=network.target

[Service]
ExecStart=${BIN_PATH} -c ${INSTALL_DIR}/config.json
Restart=always
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

SERVICE_STATUS="systemd"

# ===== OpenRC (Alpine) =====
else
cat > /etc/init.d/${SERVICE_NAME} <<EOF
#!/sbin/openrc-run
command="${BIN_PATH}"
command_args="-c ${INSTALL_DIR}/config.json"
pidfile="/run/${SERVICE_NAME}.pid"

depend() {
    need net
}
EOF

chmod +x /etc/init.d/${SERVICE_NAME}
rc-update add ${SERVICE_NAME}
rc-service ${SERVICE_NAME} start

SERVICE_STATUS="openrc"
fi

# ===== 获取IP =====
IPV4=$(curl -s -4 ifconfig.me || echo "IPv4获取失败")
IPV6=$(curl -s -6 ifconfig.me || echo "IPv6获取失败")

# ===== 输出链接 =====
echo ""
echo "====== 安装完成 ======"
echo "UUID: $UUID"
echo "PASSWORD: $PASSWORD"
echo "PORT: $PORT"
echo ""

echo "=== v2rayN IPv4 ==="
echo "tuic://${UUID}:${PASSWORD}@${IPV4}:${PORT}?congestion_control=bbr&alpn=h3&allow_insecure=1#tuic-ipv4"

echo ""
echo "=== v2rayN IPv6 ==="
echo "tuic://${UUID}:${PASSWORD}@[${IPV6}]:${PORT}?congestion_control=bbr&alpn=h3&allow_insecure=1#tuic-ipv6"