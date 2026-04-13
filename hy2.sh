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

# 重启服务
restart_service() {
    if [ "$OS" = "alpine" ]; then
        rc-service hysteria restart
    else
        systemctl restart hysteria
    fi
}

# 获取并显示信息 (双栈支持)
show_info() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}❌ Hysteria2 未安装${NC}"
        return
    fi
    PORT=$(cat "$PORT_FILE")
    PASSWORD=$(cat "$PASS_FILE")
    
    # 分别获取 IPv4 和 IPv6
    IP4=$(curl -s4 https://api.ipify.org || curl -s4 ifconfig.me || echo "未检测到IPv4")
    IP6=$(curl -s6 https://api64.ipify.org || curl -s6 ifconfig.me || echo "")

    echo -e "\n${GREEN}========== Hysteria2 配置信息 ==========${NC}"
    echo -e "📌 IPv4 地址: ${YELLOW}$IP4${NC}"
    [[ -n "$IP6" ]] && echo -e "📌 IPv6 地址: ${YELLOW}$IP6${NC}"
    echo -e "🎲 监听端口: ${YELLOW}$PORT${NC}"
    echo -e "🔐 验证密码: ${YELLOW}$PASSWORD${NC}"
    
    echo -e "\n${GREEN}📎 节点链接 (IPv4):${NC}"
    echo -e "${YELLOW}hy2://$PASSWORD@$IP4:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#${TAG}_V4${NC}"
    
    if [[ -n "$IP6" ]]; then
        echo -e "\n${GREEN}📎 节点链接 (IPv6):${NC}"
        echo -e "${YELLOW}hy2://$PASSWORD@[$IP6]:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#${TAG}_V6${NC}"
    fi
    echo -e "${GREEN}=======================================${NC}\n"
}

# 更改端口 (手动或随机)
change_port() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}❌ 请先安装 Hysteria2${NC}"; return
    fi
    OLD_PORT=$(cat "$PORT_FILE")
    echo -e "当前端口为: ${YELLOW}$OLD_PORT${NC}"
    read -p "请输入新端口 (直接回车则随机生成 10000-65535): " NEW_PORT
    
    if [ -z "$NEW_PORT" ]; then
        NEW_PORT=$(( ( RANDOM % 55535 ) + 10000 ))
    fi

    if [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        echo -e "${RED}❌ 输入无效${NC}"; return
    fi

    sed -i "s/listen: :$OLD_PORT/listen: :$NEW_PORT/g" "$CONF"
    echo "$NEW_PORT" > "$PORT_FILE"
    
    # 尝试放行防火墙
    command -v ufw >/dev/null 2>&1 && ufw allow "$NEW_PORT"/udp
    
    restart_service
    echo -e "${GREEN}✅ 端口已更改为 $NEW_PORT${NC}"
    echo -e "${GREEN}✅ hysteria2 服务已重启"
    show_info
}

# 安装
install_hy2() {
    echo -e "${YELLOW}▶ 正在安装依赖...${NC}"
    [ "$OS" = "alpine" ] && apk add --no-cache curl openssl ca-certificates bash || (apt update && apt install -y curl openssl ca-certificates bash)
    
    mkdir -p "$WORKDIR"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) FILE="hysteria-linux-amd64" ;;
        aarch64) FILE="hysteria-linux-arm64" ;;
        *) echo "❌ 不支持的架构"; exit 1 ;;
    esac

    echo -e "${YELLOW}▶ 下载 Hysteria2 主程序...${NC}"
    curl -L -o "$BIN" "https://github.com/apernet/hysteria/releases/latest/download/$FILE"
    chmod +x "$BIN"

    # 生成随机密码和 10000 以上随机端口
    PASSWORD=$(openssl rand -hex 4)
    PORT=$(( ( RANDOM % 55535 ) + 10000 ))
    echo "$PASSWORD" > "$PASS_FILE"
    echo "$PORT" > "$PORT_FILE"

    echo -e "${YELLOW}▶ 生成自签证书...${NC}"
    openssl req -x509 -nodes -newkey rsa:2048 -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" -days 3650 -subj "/CN=$SERVER_NAME"

    # 写入配置
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

    # 服务部署
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
    echo -e "${GREEN}✅ Hysteria2 安装完成！${NC}"
    show_info
}

# 卸载
uninstall_hy2() {
    echo -e "${YELLOW}▶ 正在清理系统...${NC}"
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

# --- 菜单界面 ---
clear
echo -e "${GREEN}Hysteria2 管理脚本${NC}"
echo "--------------------------"
echo "1. 安装 Hysteria2"
echo "2. 查看配置信息"
echo "3. 更改监听端口"
echo "4. 重启服务"
echo "5. 卸载 Hysteria2"
echo "0. 退出"
echo "--------------------------"
read -p "请输入数字选择: " choice

case $choice in
    1) install_hy2 ;;
    2) show_info ;;
    3) change_port ;;
    4) restart_service && echo -e "${GREEN}服务已重启${NC}" ;;
    5) uninstall_hy2 ;;
    *) exit 0 ;;
esac
