#!/usr/bin/env bash
set -e

### ===== 可修改参数 =====
SERVER_NAME="www.bing.com"
TAG="HY2"
WORKDIR="/etc/hysteria"
BIN="/usr/local/bin/hysteria"
CONF="$WORKDIR/config.yaml"
PORT_FILE="$WORKDIR/port.txt"
### =====================

# 必须 root
if [ "$(id -u)" != "0" ]; then
    echo "❌ 请使用 root 运行"
    exit 1
fi

# 判断系统
if command -v apk >/dev/null 2>&1; then
    OS="alpine"
elif command -v apt >/dev/null 2>&1; then
    OS="debian"
else
    echo "❌ 仅支持 Alpine / Debian / Ubuntu"
    exit 1
fi

echo "▶ 当前系统: $OS"

# 安装依赖
if [ "$OS" = "alpine" ]; then
    apk add --no-cache curl openssl ca-certificates bash
else
    apt update
    apt install -y curl openssl ca-certificates bash
fi

PASSWORD=$(openssl rand -hex 4)
mkdir -p "$WORKDIR"

# BBR开启检测
if [ "$OS" != "alpine" ] && [ "$(sysctl -n net.core.default_qdisc)" != "fq" ]; then
    echo "▶ 开启内核 BBR..."
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# 端口（仅首次生成）
if [ ! -f "$PORT_FILE" ]; then
    PORT=$(( ( RANDOM % 40000 ) + 20000 ))
    echo "$PORT" > "$PORT_FILE"
else
    PORT=$(cat "$PORT_FILE")
fi

# IPv4
IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
[ -z "$IP" ] && { echo "❌ 获取 IPv4 失败"; exit 1; }

# IPv6（可选）
IPV6=$(curl -6 -s https://api64.ipify.org 2>/dev/null || true)

# 下载 hysteria
echo "▶ 下载 Hysteria2..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) FILE="hysteria-linux-amd64" ;;
  aarch64) FILE="hysteria-linux-arm64" ;;
  *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

curl -L -o "$BIN" "https://github.com/apernet/hysteria/releases/latest/download/$FILE"
chmod +x "$BIN"

# 证书
echo "▶ 生成自签证书..."
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$WORKDIR/key.pem" \
  -out "$WORKDIR/cert.pem" \
  -days 3650 \
  -subj "/CN=$SERVER_NAME"

# 配置文件
echo "▶ 写入配置文件..."
cat > "$CONF" <<EOF
# 监听端口
listen: :$PORT

# 自签证书
tls:
  cert: $WORKDIR/cert.pem
  key: $WORKDIR/key.pem
  alpn:
    - h3

# 密码
auth:
  type: password
  password: "$PASSWORD"

# QUIC 优化
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  maxIncomingStreams: 1024

# UDP转发
udpIdleTimeout: 60s

# DNS（防污染）
resolver:
  type: tcp
  tcp:
    addr: 208.67.222.222:53
EOF

# ===== 服务管理 =====
if [ "$OS" = "alpine" ]; then
    echo "▶ 配置 OpenRC（Alpine）"

    cat > /etc/init.d/hysteria <<'EOF'
#!/sbin/openrc-run

name="hysteria"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background=true
pidfile="/run/hysteria.pid"
supervisor="supervise-daemon"

depend() {
    need net
}
EOF

    chmod +x /etc/init.d/hysteria
    rc-update add hysteria default
    rc-service hysteria restart

else
    echo "▶ 配置 systemd（Debian / Ubuntu）"

    cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=$BIN server -c $CONF
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hysteria
    systemctl restart hysteria
fi

# 链接
LINK_V4="hy2://$PASSWORD@$IP:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#${TAG}-IPv4"
[ -n "$IPV6" ] && LINK_V6="hy2://$PASSWORD@[$IPV6]:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#${TAG}-IPv6"

# 定义颜色变量
GREEN='\e[32m'
NC='\e[0m'

echo
echo "=============================="
echo "✅ Hysteria2 安装完成"
echo "🖥 系统: $OS"
echo "📌 IPv4: $IP"
[ -n "$IPV6" ] && echo "📌 IPv6: $IPV6"
echo "🎲 端口: $PORT"
echo "🔐 密码: $PASSWORD"
echo "📎 hy2 链接："
# 使用 -e 参数激活转义字符
echo -e "${GREEN}${LINK_V4}${NC}"
[ -n "$IPV6" ] && echo -e "${GREEN}${LINK_V6}${NC}"
echo "=============================="
