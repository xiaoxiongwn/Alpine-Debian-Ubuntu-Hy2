#!/usr/bin/env bash
set -e

### ===== 可修改参数 =====
TAG="ShadowQUIC"
WORKDIR="/etc/shadowquic"
BIN="/usr/local/bin/shadowquic"
CONF="$WORKDIR/config.json"
PORT_FILE="$WORKDIR/port.txt"
PASSWORD_LEN=16
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
    apk add --no-cache curl ca-certificates bash
else
    apt update
    apt install -y curl ca-certificates bash
fi

mkdir -p "$WORKDIR"

PASSWORD=$(head -c 32 /dev/urandom | tr -dc A-Za-z0-9 | head -c $PASSWORD_LEN)

# 随机端口（仅首次）
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

# 下载 ShadowQUIC
echo "▶ 下载 ShadowQUIC..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) FILE="shadowquic-linux-amd64" ;;
  aarch64) FILE="shadowquic-linux-arm64" ;;
  *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

curl -L -o "$BIN" "https://github.com/shadowquic/shadowquic/releases/latest/download/$FILE"
chmod +x "$BIN"

# 配置文件
echo "▶ 写入配置文件..."
cat > "$CONF" <<EOF
{
  "mode": "server",
  "listen": "0.0.0.0:$PORT",
  "password": "$PASSWORD",
  "log_level": "info"
}
EOF

# ===== 服务管理 =====
if [ "$OS" = "alpine" ]; then
    echo "▶ 配置 OpenRC"

    cat > /etc/init.d/shadowquic <<'EOF'
#!/sbin/openrc-run

name="shadowquic"
command="/usr/local/bin/shadowquic"
command_args="-c /etc/shadowquic/config.json"
command_background=true
pidfile="/run/shadowquic.pid"
supervisor="supervise-daemon"

depend() {
    need net
}
EOF

    chmod +x /etc/init.d/shadowquic
    rc-update add shadowquic default
    rc-service shadowquic restart

else
    echo "▶ 配置 systemd"

    cat > /etc/systemd/system/shadowquic.service <<EOF
[Unit]
Description=ShadowQUIC Server
After=network.target

[Service]
ExecStart=$BIN -c $CONF
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowquic
    systemctl restart shadowquic
fi

# 链接（标准 shadowquic 格式）
LINK_V4="shadowquic://$PASSWORD@$IP:$PORT#$TAG"
[ -n "$IPV6" ] && LINK_V6="shadowquic://$PASSWORD@[$IPV6]:$PORT#${TAG}-IPv6"

echo
echo "=============================="
echo "✅ ShadowQUIC 安装完成"
echo "🖥 系统: $OS"
echo "📌 IPv4: $IP"
[ -n "$IPV6" ] && echo "📌 IPv6: $IPV6"
echo "🎲 端口: $PORT"
echo "🔐 密码: $PASSWORD"
echo "📎 链接："
echo "$LINK_V4"
[ -n "$IPV6" ] && echo "$LINK_V6"
echo "=============================="
