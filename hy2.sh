#!/usr/bin/env bash
set -e

SERVER_NAME="[www.bing.com](http://www.bing.com)"
TAG="HY2"
WORKDIR="/etc/hysteria"
BIN="/usr/local/bin/hysteria"
CONF="$WORKDIR/config.yaml"
PORT_FILE="$WORKDIR/port.txt"
SERVICE="hysteria"

green() { echo -e "\033[32m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }

check_root() {
[ "$(id -u)" != "0" ] && { red "❌ 请用 root 运行"; exit 1; }
}

detect_os() {
if command -v apk >/dev/null; then
OS="alpine"
elif command -v apt >/dev/null; then
OS="debian"
else
red "❌ 不支持系统"
exit 1
fi
}

install_base() {
if [ "$OS" = "alpine" ]; then
apk add --no-cache curl openssl bash ca-certificates
else
apt update -y
apt install -y curl openssl bash ca-certificates
fi
}

install_hy2() {
check_root
detect_os
green "▶ 开始安装 ($OS)"

```
install_base
mkdir -p "$WORKDIR"

# 端口
if [ ! -f "$PORT_FILE" ]; then
    while :; do
        PORT=$((RANDOM%40000+20000))
        ss -lun | grep -q ":$PORT " || break
    done
    echo "$PORT" > "$PORT_FILE"
else
    PORT=$(cat "$PORT_FILE")
fi

IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
IPV6=$(curl -6 -s https://api64.ipify.org 2>/dev/null || true)
PASSWORD=$(openssl rand -hex 8)

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) FILE="hysteria-linux-amd64" ;;
  aarch64) FILE="hysteria-linux-arm64" ;;
  *) red "❌ 架构不支持"; exit 1 ;;
esac

curl -L -o "$BIN" https://github.com/apernet/hysteria/releases/latest/download/$FILE
chmod +x "$BIN"

# 证书
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$WORKDIR/key.pem" \
  -out "$WORKDIR/cert.pem" \
  -days 3650 \
  -subj "/CN=$SERVER_NAME"

# 配置
cat > "$CONF" <<EOF
```

listen: :$PORT

tls:
cert: $WORKDIR/cert.pem
key: $WORKDIR/key.pem
alpn:
- h3

auth:
type: password
password: "$PASSWORD"

masquerade:
type: proxy
proxy:
url: https://$SERVER_NAME
rewriteHost: true
EOF

```
# 服务
if [ "$OS" = "alpine" ]; then
    cat > /etc/init.d/$SERVICE <<'EOF'
```

#!/sbin/openrc-run
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background=true
pidfile="/run/hysteria.pid"
depend() { need net; }
EOF
chmod +x /etc/init.d/$SERVICE
rc-update add $SERVICE default
rc-service $SERVICE restart
else
cat > /etc/systemd/system/$SERVICE.service <<EOF
[Unit]
Description=Hysteria2
After=network.target

[Service]
ExecStart=$BIN server -c $CONF
Restart=always
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable $SERVICE
systemctl restart $SERVICE
fi

```
sleep 2

LINK_V4="hy2://$PASSWORD@$IP:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#$TAG"
[ -n "$IPV6" ] && LINK_V6="hy2://$PASSWORD@[$IPV6]:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#${TAG}-IPv6"

green "====== 安装完成 ======"
echo "IP: $IP"
echo "端口: $PORT"
echo "密码: $PASSWORD"
echo "$LINK_V4"
[ -n "$IPV6" ] && echo "$LINK_V6"
```

}

uninstall_hy2() {
check_root
green "▶ 卸载中..."

```
systemctl stop $SERVICE 2>/dev/null || true
systemctl disable $SERVICE 2>/dev/null || true
rm -f /etc/systemd/system/$SERVICE.service

rc-service $SERVICE stop 2>/dev/null || true
rc-update del $SERVICE 2>/dev/null || true
rm -f /etc/init.d/$SERVICE

rm -rf "$WORKDIR"
rm -f "$BIN"

green "✅ 已卸载"
```

}

status_hy2() {
if ps aux | grep hysteria | grep -v grep >/dev/null; then
green "✅ 运行中"
else
red "❌ 未运行"
fi
}

menu() {
echo
echo "====== Hysteria2 管理 ======"
echo "1. 安装"
echo "2. 卸载"
echo "3. 重装"
echo "4. 状态"
echo "0. 退出"
echo "==========================="
read -rp "请选择: " num

```
case "$num" in
    1) install_hy2 ;;
    2) uninstall_hy2 ;;
    3) uninstall_hy2 && install_hy2 ;;
    4) status_hy2 ;;
    *) exit 0 ;;
esac
```

}

# ===== 参数模式 =====

case "$1" in
install) install_hy2 ;;
uninstall) uninstall_hy2 ;;
restart) uninstall_hy2 && install_hy2 ;;
status) status_hy2 ;;
*) menu ;;
esac
