#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行此脚本!${NC}" && exit 1

# 检测系统类型
if [ -f /etc/alpine-release ]; then
    OS="alpine"
elif [ -f /etc/debian_version ]; then
    OS="debian"
else
    echo -e "${RED}不支持的系统类型。仅支持 Alpine, Debian, Ubuntu。${NC}"
    exit 1
fi

# 安装依赖
install_deps() {
    echo -e "${YELLOW}正在安装依赖...${NC}"
    if [ "$OS" = "alpine" ]; then
        apk add --no-interactive curl openssl ca-certificates bash
    else
        apt-get update && apt-get install -y curl openssl ca-certificates
    fi
}

# 卸载功能
uninstall() {
    echo -e "${YELLOW}正在卸载 Hysteria 2...${NC}"
    if [ "$OS" = "alpine" ]; then
        rc-service hysteria stop 2>/dev/null
        rc-update del hysteria default 2>/dev/null
        rm -f /etc/init.d/hysteria
    else
        systemctl stop hysteria 2>/dev/null
        systemctl disable hysteria 2>/dev/null
        rm -f /etc/systemd/system/hysteria.service
        systemctl daemon-reload
    fi
    rm -rf /usr/local/bin/hysteria
    rm -rf /etc/hysteria
    echo -e "${GREEN}卸载完成。${NC}"
    exit 0
}

if [ "$1" = "uninstall" ]; then
    uninstall
fi

install_deps

# 获取架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo -e "${RED}不支持的架构: $ARCH${NC}"; exit 1 ;;
esac

echo -e "${YELLOW}正在下载 Hysteria 2...${NC}"
URL=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep "browser_download_url.*linux-$ARCH\"" | cut -d '"' -f 4)
curl -L -o /usr/local/bin/hysteria $URL
chmod +x /usr/local/bin/hysteria

mkdir -p /etc/hysteria/certs

# 随机参数 (20000 以上)
PORT=$((RANDOM % 45036 + 20000))
PASSWORD=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)
SNI="www.bing.com"

# 生成自签名证书
openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/certs/server.key -out /etc/hysteria/certs/server.crt -subj "/CN=$SNI" -days 3650 2>/dev/null

# 创建配置
cat << EOF > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/certs/server.crt
  key: /etc/hysteria/certs/server.key
auth:
  type: password
  password: $PASSWORD
fastOpen: true
masquarade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true
EOF

# 进程守护配置
if [ "$OS" = "alpine" ]; then
    cat << EOF > /etc/init.d/hysteria
#!/sbin/openrc-run
description="Hysteria 2 Service"
command="/usr/local/bin/hysteria"
command_args="server --config /etc/hysteria/config.yaml"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/hysteria.log"
error_log="/var/log/hysteria.log"
depend() {
    need net
}
EOF
    chmod +x /etc/init.d/hysteria
    rc-update add hysteria default
    rc-service hysteria start
else
    cat << EOF > /etc/systemd/system/hysteria.service
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable hysteria
    systemctl start hysteria
fi

# 获取 IP
IPV4=$(curl -s4 --max-time 5 https://api64.ipify.org)
IPV6=$(curl -s6 --max-time 5 https://api64.ipify.org)

# 生成链接函数
gen_link() {
    local ip=$1
    local label=$2
    echo "hysteria2://$PASSWORD@$ip:$PORT/?insecure=1&sni=$SNI&alpn=h3#Hy2_$label"
}

echo -e "\n${GREEN}==========================================="
echo -e "Hysteria 2 安装完成！"
echo -e "===========================================${NC}"

if [ -n "$IPV4" ]; then
    echo -e "${YELLOW}IPv4 链接:${NC}"
    gen_link "$IPV4" "V4"
    echo ""
fi

if [ -n "$IPV6" ]; then
    echo -e "${YELLOW}IPv6 链接:${NC}"
    gen_link "[$IPV6]" "V6"
    echo ""
fi

echo -e "端口: $PORT | 密码: $PASSWORD"
echo -e "卸载: bash $0 uninstall"
echo -e "${GREEN}===========================================${NC}"
