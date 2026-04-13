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

# 颜色定义
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
NC='\e[0m'

# 权限检查
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

# --- 功能模块 ---

show_info() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}❌ Hysteria2 未安装或配置文件不存在${NC}"
        return
    fi
    PORT=$(cat "$PORT_FILE")
    PASSWORD=$(cat "$PASS_FILE")
    IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
    IPV6=$(curl -6 -s https://api64.ipify.org 2>/dev/null || true)
    
    LINK_V4="hy2://$PASSWORD@$IP:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#${TAG}-IPv4"
    
    echo -e "\n${GREEN}========== Hysteria2 配置信息 ==========${NC}"
    echo -e "📌 IPv4: ${YELLOW}$IP${NC}"
    [[ -n "$IPV6" ]] && echo -e "📌 IPv6: ${YELLOW}$IPV6${NC}"
    echo -e "🎲 端口: ${YELLOW}$PORT${NC}"
    echo -e "🔐 密码: ${YELLOW}$PASSWORD${NC}"
    echo -e "\n📎 节点链接:"
    echo -e "${GREEN}${LINK_V4}${NC}"
    [[ -n "$IPV6" ]] && echo -e "${GREEN}hy2://$PASSWORD@[$IPV6]:$PORT/?sni=$SERVER_NAME&alpn=h3&insecure=1#${TAG}-IPv6${NC}"
    echo -e "${GREEN}=======================================${NC}\n"
}

install_hy2() {
    echo -e "${YELLOW}▶ 开始安装...${NC}"
    
    # 依赖安装
    if [ "$OS" = "alpine" ]; then
        apk add --no-cache curl openssl ca-certificates bash
    else
        apt update && apt install -y curl openssl ca-certificates bash
    fi

    mkdir -p "$WORKDIR"
    
    # 资源下载
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) FILE="hysteria-linux-amd64" ;;
        aarch64) FILE="hysteria-linux-arm64" ;;
        *) echo "❌ 不支持的架构"; exit 1 ;;
    esac

    echo "▶ 下载 Hysteria2 主程序..."
    curl -L -o "$BIN" "https://github.com/apernet/hysteria/releases/latest/download/$FILE"
    chmod +x "$BIN"

    # 生成随机参数
    PASSWORD=$(openssl rand -hex 8)
    PORT=$(( ( RANDOM % 40000 ) + 20000 ))
    echo "$PASSWORD" > "$PASS_FILE"
    echo "$PORT" > "$PORT_FILE"

    # 证书生成
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

    # 服务启动
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
        rc-service hysteria restart
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
        systemctl restart hysteria
    fi
    
    echo -e "${GREEN}✅ 安装完成！${NC}"
    show_info
}

uninstall_hy2() {
    echo -e "${YELLOW}▶ 正在卸载 Hysteria2...${NC}"
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
    echo -e "${GREEN}✅ 卸载成功！相关文件已清除。${NC}"
}

# --- 交互菜单 ---
echo -e "${GREEN}Hysteria2 管理脚本${NC}"
echo "-------------------"
echo "1. 安装 Hysteria2"
echo "2. 查看配置信息"
echo "3. 卸载 Hysteria2"
echo "4. 重启服务"
echo "0. 退出"
echo "-------------------"
read -p "请输入选项: " choice

case $choice in
    1) install_hy2 ;;
    2) show_info ;;
    3) uninstall_hy2 ;;
    4) 
        if [ "$OS" = "alpine" ]; then rc-service hysteria restart; else systemctl restart hysteria; fi
        echo -e "${GREEN}服务已重启${NC}"
        ;;
    *) exit 0 ;;
esac