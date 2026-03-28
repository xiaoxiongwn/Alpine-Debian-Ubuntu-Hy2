#!/usr/bin/env bash
set -e

WORK_DIR="/usr/local/tuic"
BIN="${WORK_DIR}/tuic-server"
CONF="${WORK_DIR}/server.toml"

mkdir -p $WORK_DIR
cd $WORK_DIR

echo "🚀 TUIC 安装开始..."

# ========= 架构检测 =========
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) TUIC_ARCH="x86_64" ;;
  aarch64|arm64) TUIC_ARCH="aarch64" ;;
  armv7l) TUIC_ARCH="armv7" ;;
  *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
esac

# ========= 系统检测 =========
if [ -f /etc/alpine-release ]; then
  OS="alpine"
elif [ -f /etc/debian_version ]; then
  OS="debian"
else
  echo "❌ 不支持系统"; exit 1
fi

echo "🖥 系统: $OS | 架构: $TUIC_ARCH"

# ========= 安装依赖 =========
install_dep() {
  if [ "$OS" = "alpine" ]; then
    apk add --no-cache curl openssl iptables
  else
    apt update -y
    apt install -y curl openssl iptables
  fi
}

# ========= 下载 TUIC =========
download() {
  URL1="https://github.com/Itsusinn/tuic/releases/download/v1.7.2/tuic-server-${TUIC_ARCH}-linux"
  URL2="https://ghproxy.com/${URL1}"

  echo "📥 下载 TUIC..."
  curl -L --fail -o tuic-server $URL1 || curl -L --fail -o tuic-server $URL2

  chmod +x tuic-server
}

# ========= 生成证书 =========
gen_cert() {
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout key.pem -out cert.pem \
    -subj "/CN=www.bing.com" -days 3650 -nodes
}

# ========= 生成配置 =========
gen_conf() {
  PORT=$(shuf -i20000-60000 -n1)
  UUID=$(cat /proc/sys/kernel/random/uuid)
  PASS=$(openssl rand -hex 8)

cat > $CONF <<EOF
server = "[::]:${PORT}"

[users]
${UUID} = "${PASS}"

[tls]
certificate = "cert.pem"
private_key = "key.pem"
alpn = ["h3"]

[quic]
congestion_control = "bbr"
EOF

echo "$PORT" > port
echo "$UUID" > uuid
echo "$PASS" > pass
}

# ========= 获取IP =========
get_ip() {
  IPV4=$(curl -s4 ip.sb || echo "")
  IPV6=$(curl -s6 ip.sb || echo "")
}

# ========= 防火墙 =========
open_port() {
  PORT=$(cat port)

  iptables -I INPUT -p udp --dport $PORT -j ACCEPT || true

  if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/udp || true
  fi
}

# ========= 启动服务 =========
service_install() {

if command -v systemctl >/dev/null 2>&1; then

cat > /etc/systemd/system/tuic.service <<EOF
[Unit]
Description=TUIC
After=network.target

[Service]
ExecStart=${BIN} -c ${CONF}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable tuic
systemctl restart tuic

else

cat > /etc/init.d/tuic <<EOF
#!/sbin/openrc-run
command="${BIN}"
command_args="-c ${CONF}"
command_background=true
EOF

chmod +x /etc/init.d/tuic
rc-update add tuic default
service tuic start

fi
}

# ========= 输出链接 =========
output_link() {
  PORT=$(cat port)
  UUID=$(cat uuid)
  PASS=$(cat pass)

  echo ""
  echo "====== 节点信息 ======"

  if [ -n "$IPV4" ]; then
    echo "IPv4:"
    echo "tuic://${UUID}:${PASS}@${IPV4}:${PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC-${IPV4}"
  fi

  if [ -n "$IPV6" ]; then
    echo ""
    echo "IPv6:"
    echo "tuic://${UUID}:${PASS}@[${IPV6}]:${PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC-${IPV6}"
  fi
}

# ========= 卸载 =========
uninstall() {
  echo "🗑 卸载中..."

  systemctl stop tuic 2>/dev/null || true
  systemctl disable tuic 2>/dev/null || true

  rm -f /etc/systemd/system/tuic.service
  rm -f /etc/init.d/tuic
  rm -rf $WORK_DIR

  echo "✅ 已卸载"
  exit 0
}

# ========= 主逻辑 =========
case "${1:-}" in
  install)
    install_dep
    download
    gen_cert
    gen_conf
    get_ip
    open_port
    service_install
    output_link
    ;;
  uninstall)
    uninstall
    ;;
  *)
    echo "用法: bash tuic.sh install"
    ;;
esac
