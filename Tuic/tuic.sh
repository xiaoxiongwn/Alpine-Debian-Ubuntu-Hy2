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
        echo -e "${RED}❌ TUIC 未安装或配置文件不存在${NC}"; return
    fi
    
    # 精准提取配置信息
    PORT=$(grep "server:" "$CONF" | sed 's/.*://' | tr -d '"' | tr -d ' ' | tr -d ']')
    UUID=$(grep -A 1 "users:" "$CONF" | tail -n 1 | awk -F'"' '{print $2}')
    PASS=$(grep -A 1 "users:" "$CONF" | tail -n 1 | awk -F'"' '{print $4}')
    
    echo -e "${YELLOW}正在检测公网 IP 地址...${NC}"
    
    # 获取 IP (5秒超时，失败则留空)
    IP4=$(curl -s4 --connect-timeout 5 ip.sb || curl -s4 --connect-timeout 5 ifconfig.me || echo "")
    IP6=$(curl -s6 --connect-timeout 5 ip.sb || curl -s6 --connect-timeout 5 ifconfig.me || echo "")

    echo -e "\n${GREEN}========== TUIC 配置信息 ==========${NC}"
    echo -e "🌐 IPv4地址: ${YELLOW}$IP4${NC}"
    echo -e "🌐 IPv6地址: ${YELLOW}$IP6${NC}"
    echo -e "📌 UUID: ${YELLOW}$UUID${NC}"
    echo -e "🔐 密码: ${YELLOW}$PASS${NC}"
    echo -e "🎲 端口: ${YELLOW}$PORT${NC}"
    
    # --- IPv4 显示逻辑 ---
    if [[ -n "$IP4" ]]; then
        echo -e "\n${GREEN}📎 TUIC 节点链接 (IPv4):${NC}"
        echo -e "${YELLOW}tuic://$UUID:$PASS@$IP4:$PORT?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC_V4${NC}"
    fi
    
    # --- IPv6 显示逻辑 ---
    if [[ -n "$IP6" ]]; then
        echo -e "\n${GREEN}📎 TUIC 节点链接 (IPv6):${NC}"
        echo -e "${YELLOW}tuic://$UUID:$PASS@[$IP6]:$PORT?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC_V6${NC}"
    fi

    # 兜底：如果两个都没检测到
    if [[ -z "$IP4" && -z "$IP6" ]]; then
        echo -e "\n${RED}⚠️ 警告: 无法检测到任何公网 IP 地址，请检查服务器网络。${NC}"
    fi
    echo -e "${GREEN}=======================================${NC}\n"
}

# 修改端口
change_port() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}❌ 请先安装 TUIC${NC}"; return
    fi
    
    # 提取旧端口
    OLD_PORT=$(grep "server:" "$CONF" | sed 's/.*://' | tr -d '"' | tr -d ' ' | tr -d ']')
    
    echo -e "当前监听端口为: ${YELLOW}$OLD_PORT${NC}"
    read -p "请输入新端口 (10000-65535，直接回车则随机): " NEW_PORT
    
    [[ -z "$NEW_PORT" ]] && NEW_PORT=$(( ( RANDOM % 50000 ) + 10000 ))

    if [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        echo -e "${RED}❌ 输入无效${NC}"; return
    fi

    sed -i "s/\(:[0-9]\{1,5\}\)\"/\:$NEW_PORT\"/g" "$CONF"
    
    # 校验配置文件是否更改成功
    CHECK_PORT=$(grep "server:" "$CONF" | sed 's/.*://' | tr -d '"' | tr -d ' ' | tr -d ']')
    
    if [ "$CHECK_PORT" != "$NEW_PORT" ]; then
        echo -e "${RED}❌ 自动修改失败，正在尝试强制写入...${NC}"
        # 备用方案：通过重新生成 server 行来强制修改
        BIND_ADDR="0.0.0.0"
        grep -q "\[::\]" "$CONF" && BIND_ADDR="[::]"
        sed -i "/server:/c\server: \"${BIND_ADDR}:${NEW_PORT}\"" "$CONF"
    fi

    # 放行防火墙 (Debian 常用 ufw 或 iptables)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$NEW_PORT"/udp
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p udp --dport "$NEW_PORT" -j ACCEPT
    fi
    
    restart_service
    echo -e "${GREEN}✅ 端口已更改为 $NEW_PORT${NC}"
    echo -e "${GREEN}✅ TUIC 服务已重启"
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
    echo -e "${YELLOW}▶ 从 GitHub 官方下载 TUIC Server...${NC}"
    
    URL="https://github.com/Itsusinn/tuic/releases/latest/download/tuic-server-${TUIC_ARCH}-linux-musl"
    
    if ! curl -L -o $BIN "$URL"; then
        echo -e "${RED}❌ 下载失败，请检查服务器是否能连接 GitHub${NC}"; exit 1
    fi
    
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
