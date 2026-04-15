#!/bin/bash

# 终端颜色设置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="/etc/juicity/config.json"
BIN_FILE="/usr/local/bin/juicity-server"
SERVICE_FILE="/etc/systemd/system/juicity.service"
CERT_DIR="/etc/juicity/certs"

# 权限检查
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 请使用 root 权限运行。${NC}" && exit 1

# 1. 安装依赖 (兼容 Debian/Ubuntu 和 Alpine)
install_dependencies() {
    echo -e "${YELLOW}正在安装必要依赖...${NC}"
    if command -v apt-get >/dev/null; then
        apt-get update && apt-get install -y unzip wget openssl curl jq
    elif command -v apk >/dev/null; then
        apk add unzip wget openssl curl bash ca-certificates gcompat jq
    else
        echo -e "${RED}错误: 不支持的包管理器，请手动安装 unzip wget openssl curl jq${NC}"
        exit 1
    fi
}

# 2. 生成证书
generate_bing_cert() {
    echo -e "${YELLOW}正在生成自签证书 (www.bing.com)...${NC}"
    mkdir -p $CERT_DIR
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout $CERT_DIR/privkey.pem \
        -out $CERT_DIR/fullchain.pem \
        -days 3650 \
        -subj "/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/CN=www.bing.com" > /dev/null 2>&1
    chmod 644 $CERT_DIR/*.pem
}

# 3. 安装/更新
install_juicity() {
    install_dependencies
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  FILE_ARCH="x86_64" ;;
        aarch64) FILE_ARCH="arm64" ;;
        *) echo -e "${RED}架构不支持: $ARCH${NC}"; return ;;
    esac

    echo -e "${YELLOW}正在从 GitHub 获取最新版本...${NC}"
    DOWNLOAD_URL="https://github.com/juicity/juicity/releases/latest/download/juicity-linux-${FILE_ARCH}.zip"
    wget -qO /tmp/juicity.zip "$DOWNLOAD_URL"
    
    if [ ! -s /tmp/juicity.zip ]; then
        echo -e "${RED}下载失败，请检查网络...${NC}"
        return
    fi

    mkdir -p /tmp/juicity_bin
    unzip -qo /tmp/juicity.zip -d /tmp/juicity_bin
    find /tmp/juicity_bin -name "juicity-server" -exec mv {} $BIN_FILE \;
    chmod +x $BIN_FILE
    rm -rf /tmp/juicity.zip /tmp/juicity_bin
    
    generate_bing_cert

    # 端口及账户生成
    DEFAULT_PORT=$((RANDOM % 50000 + 10000))
    read -p "${GREEN}请输入监听端口 (默认随机 $DEFAULT_PORT): ${NC}" PORT
    PORT=${PORT:-$DEFAULT_PORT}
    
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/')
    PASS=$(openssl rand -hex 4)

    # 使用 JQ 写入配置
    mkdir -p /etc/juicity
    jq -n \
        --arg listen ":$PORT" \
        --arg uuid "$UUID" \
        --arg pass "$PASS" \
        --arg cert "$CERT_DIR/fullchain.pem" \
        --arg key "$CERT_DIR/privkey.pem" \
        '{
            listen: $listen,
            users: { ($uuid): $pass },
            certificate: $cert,
            private_key: $key,
            congestion_control: "bbr",
            alpn: ["h3"],
            log_level: "info"
        }' > $CONFIG_FILE

    # 服务管理 (Debian 使用 systemd)
    if command -v systemctl >/dev/null; then
        cat <<EOF > $SERVICE_FILE
[Unit]
Description=Juicity Server Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_FILE run -c $CONFIG_FILE
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload && systemctl enable juicity && systemctl restart juicity
    elif [ -f /sbin/openrc-run ]; then
        # Alpine OpenRC 兼容
        cat <<EOF > /etc/init.d/juicity
#!/sbin/openrc-run
description="Juicity Server"
command="$BIN_FILE"
command_args="run -c $CONFIG_FILE"
command_background=true
pidfile="/run/juicity.pid"
EOF
        chmod +x /etc/init.d/juicity
        rc-update add juicity default && rc-service juicity restart
    fi

    echo -e "${GREEN}Juicity 安装并启动成功！${NC}"
    view_config
}

# 4. 查看配置链接
view_config() {
    if [ ! -f $CONFIG_FILE ]; then
        echo -e "${RED}未发现配置文件，请先执行安装。${NC}"
        return
    fi

    # 使用 JQ 精准读取
    PORT=$(jq -r '.listen' $CONFIG_FILE | cut -d':' -f2)
    UUID=$(jq -r '.users | keys[0]' $CONFIG_FILE)
    PASS=$(jq -r --arg uuid "$UUID" '.users[$uuid]' $CONFIG_FILE)
    
    IP4=$(curl -s4 ip.sb || curl -s4 ifconfig.me)
    IP6=$(curl -s6 ip.sb || curl -s6 ifconfig.me)
    
    # 提取证书指纹
    CERT_HASH=$($BIN_FILE generate-certchain-hash --cert $CERT_DIR/fullchain.pem 2>/dev/null | head -n 1)
    [ -z "$CERT_HASH" ] && CERT_HASH=$(openssl x509 -in $CERT_DIR/fullchain.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64)

    echo -e "\n${YELLOW}====== Juicity 节点信息 ======${NC}"
    echo -e "端口: ${GREEN}${PORT}${NC}"
    echo -e "UUID: ${GREEN}${UUID}${NC}"
    echo -e "密码: ${GREEN}${PASS}${NC}"
    echo -e "ALPN: ${CYAN}h3${NC}"
    
    QUERY="congestion_control=bbr&sni=www.bing.com&alpn=h3&allow_insecure=1&pinned_certchain_sha256=${CERT_HASH}"
    
    echo -e "\n${YELLOW}--- 节点分享链接 ---${NC}"
    [ -n "$IP4" ] && echo -e "${CYAN}IPv4:${NC}\n${GREEN}juicity://${UUID}:${PASS}@${IP4}:${PORT}?${QUERY}#Juicity-V4${NC}\n"
    [ -n "$IP6" ] && echo -e "${CYAN}IPv6:${NC}\n${GREEN}juicity://${UUID}:${PASS}@[${IP6}]:${PORT}?${QUERY}#Juicity-V6${NC}\n"
}

# 5. 修改端口
change_port() {
    if [ ! -f $CONFIG_FILE ]; then echo -e "${RED}请先安装！${NC}"; return; fi
    
    OLD_PORT=$(jq -r '.listen' $CONFIG_FILE | cut -d':' -f2)
    read -p "请输入新端口 (当前 $OLD_PORT): " NEW_PORT
    
    if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -le 65535 ]; then
        TMP_FILE=$(mktemp)
        jq --arg port ":$NEW_PORT" '.listen = $port' $CONFIG_FILE > "$TMP_FILE" && mv "$TMP_FILE" $CONFIG_FILE
        
        if command -v systemctl >/dev/null; then
            systemctl restart juicity
        else
            rc-service juicity restart
        fi
        echo -e "${GREEN}端口已更改为 $NEW_PORT${NC}"
        view_config
    else
        echo -e "${RED}输入无效！${NC}"
    fi
}

# 6. 卸载
uninstall_juicity() {
    read -p "确认要彻底卸载 Juicity 吗? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        if command -v systemctl >/dev/null; then
            systemctl stop juicity && systemctl disable juicity
        else
            rc-service juicity stop && rc-update del juicity 2>/dev/null
        fi
        rm -rf /etc/juicity $BIN_FILE $SERVICE_FILE /etc/init.d/juicity
        echo -e "${GREEN}卸载完成。${NC}"
    fi
}

# 主循环菜单
while true; do
    clear
    echo -e "${YELLOW}--- Juicity 管理脚本 ---${NC}"
    echo -e "${GREEN}1. 安装/更新 Juicity${NC}"
    echo -e "${GREEN}2. 查看配置节点链接${NC}"
    echo -e "${GREEN}3. 修改监听端口${NC}"
    echo -e "${GREEN}4. 卸载 Juicity${NC}"
    echo -e "${GREEN}0. 退出脚本${NC}"
    echo "--------------------------------------"
    read -p "请选择 [0-4]: " choice

    case $choice in
        1) install_juicity; echo ""; read -p "按回车键返回主菜单..." ;;
        2) view_config; echo ""; read -p "按回车键返回主菜单..." ;;
        3) change_port; echo ""; read -p "按回车键返回主菜单..." ;;
        4) uninstall_juicity; echo ""; read -p "按回车键返回主菜单..." ;;
        0) exit 0 ;;
        *) echo -e "${RED}选择无效！${NC}"; sleep 1 ;;
    esac
done
