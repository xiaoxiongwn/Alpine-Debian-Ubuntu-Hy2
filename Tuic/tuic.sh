#!/usr/bin/env bash
set -e

WORK_DIR="/usr/local/tuic"
BIN="${WORK_DIR}/tuic-server"
CONF="${WORK_DIR}/config.yaml"
SERVICE_NAME="tuic"

# 安装函数
install_tuic() {
    echo "🚀 安装 TUIC ..."

    # 检测架构
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) TUIC_ARCH="x86_64" ;;
        aarch64|arm64) TUIC_ARCH="aarch64" ;;
        armv7l) TUIC_ARCH="armv7" ;;
        *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
    esac

    # 检测系统
    if [ -f /etc/alpine-release ]; then
        OS="alpine"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        echo "❌ 不支持的系统"; exit 1
    fi

    # 安装依赖
    if [ "$OS" = "alpine" ]; then
        apk add --no-cache curl openssl iptables bash openrc
    else
        apt update -y
        apt install -y curl openssl iptables
    fi

    mkdir -p $WORK_DIR
    cd $WORK_DIR

    # 下载 TUIC 可执行文件
    URL="https://github.com/Itsusinn/tuic/releases/latest/download/tuic-server-${TUIC_ARCH}-linux-musl"
    curl -L -o $BIN $URL || curl -L -o $BIN https://ghfast.top/$URL
    chmod +x $BIN

    # 随机端口 / UUID / 密码
    PORT=$(shuf -i20000-60000 -n1)
    UUID=$(cat /proc/sys/kernel/random/uuid)
    PASS=$(openssl rand -hex 8)

    # 检测 IPv6 支持
    if ip -6 addr >/dev/null 2>&1; then
        IPV6_SUPPORTED=true
    else
        IPV6_SUPPORTED=false
    fi

    # 生成 YAML 配置
    if $IPV6_SUPPORTED; then
        SERVER_BIND="[::]:${PORT}"
    else
        SERVER_BIND="0.0.0.0:${PORT}"
    fi

    cat > $CONF <<EOF
server: "${SERVER_BIND}"
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

    # 生成自签证书
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout key.pem -out cert.pem \
        -subj "/CN=www.bing.com" -days 3650 -nodes

    # 写入 systemd / openrc 服务
    if command -v systemctl >/dev/null; then
        cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=TUIC Server
After=network.target

[Service]
ExecStart=${BIN} -c ${CONF}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reexec
        systemctl enable ${SERVICE_NAME}
        systemctl restart ${SERVICE_NAME}
  else
        # 针对 OpenRC 的优化版
        cat > /etc/init.d/${SERVICE_NAME} <<EOF
#!/sbin/openrc-run
description="TUIC v5 Server"
command="${BIN}"
command_args="-c ${CONF}"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background=true

# 确保在启动前依赖网络
depend() {
    need net
    after firewall
}
EOF
        chmod +x /etc/init.d/${SERVICE_NAME}
        rc-update add ${SERVICE_NAME} default
        service ${SERVICE_NAME} restart
    fi

    # 检测服务运行情况
    echo "🔍 检测 TUIC 服务状态..."
    sleep 2

    if ! pgrep -f tuic-server >/dev/null; then
        echo "❌ TUIC 未运行"
        tail -n 20 /var/log/messages 2>/dev/null || journalctl -n 20
        exit 1
    fi

    if ss -luntp | grep ${PORT} >/dev/null; then
        echo "✅ 端口 ${PORT} 监听正常"
    else
        echo "⚠️ 端口 ${PORT} 未监听"
    fi

    # 输出节点信息
    IPV4=$(curl -s4 ip.sb || true)
    IPV6=$(curl -s6 ip.sb || true)

    echo ""
    echo "====== TUIC 节点信息 ======"
    if [ -n "$IPV4" ]; then
        echo "tuic://${UUID}:${PASS}@${IPV4}:${PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC-IPV4"
    fi
    if $IPV6_SUPPORTED && [ -n "$IPV6" ]; then
        echo "tuic://${UUID}:${PASS}@[${IPV6}]:${PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC-IPV6"
    fi

    echo ""
    echo "✅ 安装完成"
}

# 卸载函数
uninstall_tuic() {
    echo "🗑️ 卸载 TUIC..."

    if command -v systemctl >/dev/null; then
        systemctl stop ${SERVICE_NAME} || true
        systemctl disable ${SERVICE_NAME} || true
        rm -f /etc/systemd/system/${SERVICE_NAME}.service
        systemctl daemon-reexec
    else
        service ${SERVICE_NAME} stop || true
        rc-update del ${SERVICE_NAME} || true
        rm -f /etc/init.d/${SERVICE_NAME}
    fi

    rm -rf $WORK_DIR
    echo "✅ TUIC 已完全卸载"
}

# 主逻辑
if [[ "$1" == "uninstall" ]]; then
    uninstall_tuic
else
    install_tuic
fi
