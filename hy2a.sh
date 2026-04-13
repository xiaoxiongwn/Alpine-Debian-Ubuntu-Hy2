#!/usr/bin/env bash
set -e

### ===== 配置参数 =====
SERVER_NAME="www.bing.com"
TAG="HY2"
WORKDIR="/etc/hysteria"
BIN="/usr/local/bin/hysteria"
CONF="$WORKDIR/config.yaml"
PORT_FILE="$WORKDIR/port.txt"
PASS_FILE="$WORKDIR/password.txt"
### =====================

GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
NC='\e[0m'

[[ "$(id -u)" != "0" ]] && { echo -e "${RED}❌ 请使用 root 运行${NC}"; exit 1; }

# 环境判断
if command -v apk >/dev/null 2>&1; then
    OS="alpine"
elif command -v apt >/dev/null 2>&1; then
    OS="debian"
else
    echo -e "${RED}❌ 仅支持 Alpine / Debian / Ubuntu${NC}"
    exit 1
fi

# 重启服务函数
restart_service() {
    if [ "$OS" = "alpine" ]; then
        rc-service hysteria restart
    else
        systemctl restart hysteria
    fi
}

# 查看信息函数
show_info() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}❌ Hysteria2 未安装${NC}"
        return
    fi
    PORT=$(cat "$PORT_FILE")
    PASSWORD=$(cat "$PASS_FILE")
    IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
    
    echo -e "\n${GREEN}========== Hysteria2 配置信息 ==========${NC}"
    echo -e "📌 当前端口: ${YELLOW}$PORT${NC}"
    echo -e "🔐 当前密码: ${YELLOW}$PASSWORD${NC}"
    echo -e "\n📎 IPv4 链接:"
    echo -e "${GREEN}hy2://$PASSWORD@$IP:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#${TAG}${NC}"
    echo -e "${GREEN}=======================================${NC}\n"
}

# 修改端口函数
change_port() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}❌ 请先安装 Hysteria2${NC}"
        return
    fi
    OLD_PORT=$(cat "$PORT_FILE")
    echo -e "当前监听端口为: ${YELLOW}$OLD_PORT${NC}"
    read -p "请输入新端口 (1-65535): " NEW_PORT
    
    if [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        echo -e "${RED}❌ 输入无效${NC}"
        return
    fi

    # 修改配置文件 (使用 sed 替换 listen 行)
    sed -i "s/listen: :$OLD_PORT/listen: :$NEW_PORT/g" "$CONF"
    echo "$NEW_PORT" > "$PORT_FILE"
    
    # 防火墙处理
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$NEW_PORT"/udp
    fi

    restart_service
    echo -e "${GREEN}✅ 端口已修改为 $NEW_PORT 并已重启服务${NC}"
    show_info
}

# 安装函数
install_hy2() {
    echo -e "${YELLOW}▶ 开始安装...${NC}"
    [ "$OS" = "alpine" ] && apk add --no-cache curl openssl ca-certificates bash || (apt update && apt install -y curl openssl ca-certificates bash)
    
    mkdir -p "$WORKDIR"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) FILE="hysteria-linux-amd64" ;;
        aarch64) FILE="hysteria-linux-arm64" ;;
        *) echo "❌ 不支持的架构"; exit 1 ;;
    esac

    curl -L -o "$BIN" "https://github.com/apernet/hysteria/releases/latest/download/$FILE"
    chmod +x "$BIN"

    PASSWORD=$(openssl rand -hex 8)
    PORT=$(( ( RANDOM % 40000 ) + 20000 ))
    echo "$PASSWORD" > "$PASS_FILE"
    echo "$PORT" > "$PORT_FILE"

    openssl req -x509 -nodes -newkey rsa:2048 -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" -days 3650 -subj "/CN=$SERVER_NAME"

    cat > "$CONF" <<EOF
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
    url: https://www.bing.com
    rewriteHost: true
EOF

    if [ "$OS" = "alpine" ]; then
        cat > /etc/init.d/hysteria <<EOF
#!/sbin/openrc-run
name="hysteria"
command="$BIN"
command_args="server -c $CONF"
command_background=true
pidfile="/run/hysteria.pid"
supervisor="supervise-daemon"
EOF
        chmod +x /etc/init.d/hysteria
        rc-update add hysteria default
    else
        cat > /etc/systemd/system/hysteria.service <<EOF
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
        systemctl enable hysteria
    fi
    
    restart_service
    echo -e "${GREEN}✅ 安装完成！${NC}"
    show_info
}

# 卸载函数
uninstall_hy2() {
    echo -e "${YELLOW}▶ 正在卸载...${NC}"
    if [ "$OS" = "alpine" ]; then
        rc-service hysteria stop || true
        rc-update del hysteria || true
        rm -f /etc/init.d/hysteria
    else
        systemctl stop hysteria || true
        systemctl disable hysteria || true
        rm -f /etc/systemd/system/hysteria.service
        systemctl daemon-reload
    fi
    rm -rf "$WORKDIR"
    rm -f "$BIN"
    echo -e "${GREEN}✅ 卸载成功${NC}"
}

# --- 主菜单 ---
clear
echo -e "${GREEN}Hysteria2 管理脚本 V2.0${NC}"
echo "--------------------------"
echo "1. 安装 Hysteria2"
echo "2. 查看配置信息"
echo "3. 修改监听端口"
echo "4. 重启服务"
echo "5. 卸载 Hysteria2"
echo "0. 退出"
echo "--------------------------"
read -p "请选择: " choice

case $choice in
    1) install_hy2 ;;
    2) show_info ;;
    3) change_port ;;
    4) restart_service && echo -e "${GREEN}服务已重启${NC}" ;;
    5) uninstall_hy2 ;;
    *) exit 0 ;;
esac
