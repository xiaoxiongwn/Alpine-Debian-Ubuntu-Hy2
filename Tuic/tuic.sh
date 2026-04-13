#!/usr/bin/env bash
set -e

### ===== 配置参数 =====
WORK_DIR="/usr/local/tuic"
BIN="${WORK_DIR}/tuic-server"
CONF="${WORK_DIR}/config.yaml"
SERVICE_NAME="tuic"
### =====================

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

[[ "$(id -u)" != "0" ]] && { echo -e "${RED}❌ 请使用 root 运行${NC}"; exit 1; }

# 环境判断
if [ -f /etc/alpine-release ]; then
    OS="alpine"
elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
    OS="debian"
else
    echo -e "${RED}❌ 不支持的系统${NC}"; exit 1
fi

# 重启服务
restart_service() {
    if command -v systemctl >/dev/null; then
        systemctl restart ${SERVICE_NAME}
    else
        rc-service ${SERVICE_NAME} restart
    fi
}

# 获取并显示信息
show_info() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}❌ TUIC 未安装${NC}"; return
    fi
    
    # 使用 sed 提取最后一个冒号后的端口号
    PORT=$(grep "server:" "$CONF" | sed 's/.*://' | tr -d '"' | tr -d ' ' | tr -d ']')
    # 提取用户 ID (UUID)
    UUID=$(grep -A 1 "users:" "$CONF" | tail -n 1 | awk -F'"' '{print $2}')
    # 提取密码 (Password)
    PASS=$(grep -A 1 "users:" "$CONF" | tail -n 1 | awk -F'"' '{print $4}')
    
    IPV4=$(curl -s4 --connect-timeout 8 ip.sb || curl -s4 --connect-timeout 8 ifconfig.me || echo "未检测到")
    IPV6=$(curl -s6 --connect-timeout 8 ip.sb || curl -s6 --connect-timeout 8 ifconfig.me || echo "")

    echo -e "\n${GREEN}========== TUIC 配置信息 ==========${NC}"
    echo -e "📌 UUID: ${YELLOW}$UUID${NC}"
    echo -e "🔐 PASS: ${YELLOW}$PASS${NC}"
    echo -e "🎲 端口: ${YELLOW}$PORT${NC}"
    
    echo -e "\n${GREEN}📎 IPv4 链接:${NC}"
    echo -e "${YELLOW}tuic://$UUID:$PASS@$IPV4:$PORT?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC_V4${NC}"
    
    if [[ -n "$IPV6" && "$IPV6" != "未检测到" ]]; then
        echo -e "\n${GREEN}📎 IPv6 链接:${NC}"
        echo -e "${YELLOW}tuic://$UUID:$PASS@[$IPV6]:$PORT?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC_V6${NC}"
    fi
    echo -e "${GREEN}=======================================${NC}\n"
}

# 修改端口
change_port() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}❌ 请先安装 TUIC${NC}"; return
    fi
    
    # 获取旧端口
    OLD_PORT=$(grep "server:" "$CONF" | cut -d':' -f3 | tr -d '"' | tr -d ']')
    echo -e "当前监听端口为: ${YELLOW}$OLD_PORT${NC}"
    read -p "请输入新端口 (10000-65535，回车随机): " NEW_PORT
    
    if [ -z "$NEW_PORT" ]; then
        NEW_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
    fi

    if [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        echo -e "${RED}❌ 输入无效${NC}"; return
    fi

    # 替换配置文件中的端口
    sed -i "s/:$OLD_PORT/:$NEW_PORT/g" "$CONF"
    
    # 防火墙
    command -v ufw >/dev/null 2>&1 && ufw allow "$NEW_PORT"/udp
    
    restart_service
    echo -e "${GREEN}✅ 端口已更改为 $NEW_PORT${NC}"
    echo -e "${GREEN}✅ TUIC服务已重启"
    show_info
}

# 安装
install_tuic() {
    echo -e "${YELLOW}▶ 正在安装依赖...${NC}"
    [ "$OS" = "alpine" ] && apk add --no-cache curl openssl bash openrc || (apt update -y && apt install -y curl openssl)

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) TUIC_ARCH="x86_64" ;;
        aarch64|arm64) TUIC_ARCH="aarch64" ;;
        *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
    esac

    mkdir -p $WORK_DIR
    echo -e "${YELLOW}▶ 下载 TUIC Server...${NC}"
    URL="https://github.com/Itsusinn/tuic/releases/latest/download/tuic-server-${TUIC_ARCH}-linux-musl"
    curl -L -o $BIN $URL || curl -L -o $BIN https://ghfast.top/$URL
    chmod +x $BIN

    PORT=$(( ( RANDOM % 50000 ) + 10000 ))
    UUID=$(cat /proc/sys/kernel/random/uuid)
    PASS=$(openssl rand -hex 4)
    BIND_ADDR="0.0.0.0"
    ip -6 addr | grep -q "global" && BIND_ADDR="[::]"

    cat > $CONF <<EOF
server: "${BIND_ADDR}:${PORT}"
users:
  "${UUID}": "${PASS}"
congestion_control: "bbr"
auth_timeout: "3s"
zero_rtt_handshake: false
tls:
  certificate: "${WORK_DIR}/cert.pem"
  private_key: "${WORK_DIR}/key.pem"
  alpn:
    - "h3"
EOF

    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "${WORK_DIR}/key.pem" -out "${WORK_DIR}/cert.pem" \
        -subj "/CN=www.bing.com" -days 3650 -nodes

    if command -v systemctl >/dev/null; then
        cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=TUIC Server
After=network.target
[Service]
ExecStart=${BIN} -c ${CONF}
Restart=always
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ${SERVICE_NAME}
    else
        cat > /etc/init.d/${SERVICE_NAME} <<EOF
#!/sbin/openrc-run
description="TUIC v5 Server"
command="${BIN}"
command_args="-c ${CONF}"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background=true
depend() {
    need net
}
EOF
        chmod +x /etc/init.d/${SERVICE_NAME}
        rc-update add ${SERVICE_NAME} default
    fi

    restart_service
    echo -e "${GREEN}✅ 安装完成${NC}"
    show_info
}

# 卸载
uninstall_tuic() {
    if command -v systemctl >/dev/null; then
        systemctl stop ${SERVICE_NAME} || true
        systemctl disable ${SERVICE_NAME} || true
        rm -f /etc/systemd/system/${SERVICE_NAME}.service
        systemctl daemon-reload
    else
        rc-service ${SERVICE_NAME} stop || true
        rc-update del ${SERVICE_NAME} || true
        rm -f /etc/init.d/${SERVICE_NAME}
    fi
    rm -rf $WORK_DIR
    echo -e "${GREEN}✅ 卸载成功${NC}"
}

# --- 菜单 ---
clear
echo -e "${GREEN}TUIC 管理脚本${NC}"
echo "--------------------------"
echo "1. 安装 TUIC"
echo "2. 查看配置信息"
echo "3. 更改监听端口"
echo "4. 重启服务"
echo "5. 卸载 TUIC"
echo "0. 退出"
echo "--------------------------"
read -p "请选择: " choice

case $choice in
    1) install_tuic ;;
    2) show_info ;;
    3) change_port ;;
    4) restart_service && echo -e "${GREEN}服务已重启${NC}" ;;
    5) uninstall_tuic ;;
    *) exit 0 ;;
esac
