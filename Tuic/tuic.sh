#!/usr/bin/env bash

# ========= 基础变量 =========
MASQ_DOMAIN="www.bing.com"
WORK_DIR="/usr/local/tuic"
BIN_NAME="tuic-server"
CONFIG_FILE="${WORK_DIR}/server.toml"
CERT="${WORK_DIR}/cert.pem"
KEY="${WORK_DIR}/key.pem"

mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# ========= 检测架构 =========
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) TUIC_ARCH="x86_64" ;;
  aarch64 | arm64) TUIC_ARCH="aarch64" ;;
  *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ========= 检测系统 =========
if [ -f /etc/alpine-release ]; then
  OS="alpine"
elif [ -f /etc/debian_version ]; then
  OS="debian"
else
  echo "❌ Unsupported OS"
  exit 1
fi

echo "🖥 OS: $OS | ARCH: $TUIC_ARCH"

# ========= 安装依赖 =========
install_dep() {
  if [ "$OS" = "alpine" ]; then
    apk add --no-cache curl openssl
  else
    apt update -y
    apt install -y curl openssl
  fi
}

# ========= 下载 TUIC =========
download_tuic() {
  if [ ! -f "${BIN_NAME}" ]; then
    echo "📥 Downloading TUIC..."
    curl -L -o ${BIN_NAME} \
      https://github.com/Itsusinn/tuic/releases/download/v1.7.2/tuic-server-${TUIC_ARCH}-linux
    chmod +x ${BIN_NAME}
  fi
}

# ========= 生成证书 =========
gen_cert() {
  if [ ! -f "$CERT" ]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout "$KEY" -out "$CERT" \
      -subj "/CN=${MASQ_DOMAIN}" -days 3650 -nodes
  fi
}

# ========= 生成配置 =========
gen_config() {
  PORT=$(shuf -i20000-60000 -n1)
  UUID=$(cat /proc/sys/kernel/random/uuid)
  PASS=$(openssl rand -hex 16)

cat > ${CONFIG_FILE} <<EOF
server = "[::]:${PORT}"

[users]
${UUID} = "${PASS}"

[tls]
certificate = "${CERT}"
private_key = "${KEY}"
alpn = ["h3"]

[quic]
congestion_control = "bbr"
EOF

echo "PORT=${PORT}" > info.txt
echo "UUID=${UUID}" >> info.txt
echo "PASS=${PASS}" >> info.txt
}

# ========= 获取IP =========
get_ip() {
  IPV4=$(curl -s4 ip.sb || true)
  IPV6=$(curl -s6 ip.sb || true)
}

# ========= 生成链接 =========
gen_link() {
  source info.txt

  echo ""
  echo "====== TUIC 节点 ======"

  if [ -n "$IPV4" ]; then
    echo "IPv4:"
    echo "tuic://${UUID}:${PASS}@${IPV4}:${PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=${MASQ_DOMAIN}#TUIC-${IPV4}"
  fi

  if [ -n "$IPV6" ]; then
    echo ""
    echo "IPv6:"
    echo "tuic://${UUID}:${PASS}@[${IPV6}]:${PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=${MASQ_DOMAIN}#TUIC-${IPV6}"
  fi
}

# ========= 启动服务 =========
install_service() {

if [ "$OS" = "alpine" ]; then

cat > /etc/init.d/tuic <<EOF
#!/sbin/openrc-run
command="${WORK_DIR}/${BIN_NAME}"
command_args="-c ${CONFIG_FILE}"
command_background=true
EOF

chmod +x /etc/init.d/tuic
rc-update add tuic default
service tuic start

else

cat > /etc/systemd/system/tuic.service <<EOF
[Unit]
Description=TUIC Service
After=network.target

[Service]
ExecStart=${WORK_DIR}/${BIN_NAME} -c ${CONFIG_FILE}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable tuic
systemctl restart tuic

fi
}

# ========= 卸载 =========
uninstall() {
  echo "🗑 Uninstalling TUIC..."

  if [ "$OS" != "alpine" ]; then
    systemctl stop tuic || true
    systemctl disable tuic || true
    rm -f /etc/systemd/system/tuic.service
  else
    service tuic stop || true
    rc-update del tuic || true
    rm -f /etc/init.d/tuic
  fi

  rm -rf ${WORK_DIR}
  echo "✅ Uninstalled"
  exit 0
}

# ========= 主逻辑 =========
case "${1:-}" in
  install)
    install_dep
    download_tuic
    gen_cert
    gen_config
    get_ip
    install_service
    gen_link
    ;;
  uninstall)
    uninstall
    ;;
  *)
    echo "Usage:"
    echo "  bash tuic.sh install"
    echo "  bash tuic.sh uninstall"
    ;;
esac
