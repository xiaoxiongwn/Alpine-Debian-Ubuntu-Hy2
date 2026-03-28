#!/usr/bin/env bash
set -e

WORK_DIR="/usr/local/tuic"
BIN="${WORK_DIR}/tuic-server"
CONF="${WORK_DIR}/config.json"

mkdir -p $WORK_DIR
cd $WORK_DIR

echo "🚀 安装 TUIC ..."

# ========= 架构 =========
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) TUIC_ARCH="x86_64" ;;
  aarch64|arm64) TUIC_ARCH="aarch64" ;;
  armv7l) TUIC_ARCH="armv7" ;;
  *) echo "❌ 不支持架构"; exit 1 ;;
esac

# ========= 系统 =========
if [ -f /etc/alpine-release ]; then
  OS="alpine"
else
  OS="debian"
fi

# ========= 安装依赖 =========
if [ "$OS" = "alpine" ]; then
  apk add --no-cache curl openssl iptables
else
  apt update -y
  apt install -y curl openssl iptables
fi

# ========= 下载 =========
URL="https://github.com/Itsusinn/tuic/releases/download/v1.7.2/tuic-server-${TUIC_ARCH}-linux"
curl -L -o tuic-server $URL || curl -L -o tuic-server https://ghproxy.com/$URL
chmod +x tuic-server

# ========= 生成配置 =========
PORT=$(shuf -i20000-60000 -n1)
UUID=$(cat /proc/sys/kernel/random/uuid)
PASS=$(openssl rand -hex 8)

cat > $CONF <<EOF
{
  "server": "[::]:${PORT}",
  "users": {
    "${UUID}": "${PASS}"
  },
  "tls": {
    "certificate": "cert.pem",
    "private_key": "key.pem",
    "alpn": ["h3"]
  },
  "quic": {
    "congestion_control": "bbr"
  }
}
EOF

# ========= 证书 =========
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
-keyout key.pem -out cert.pem \
-subj "/CN=www.bing.com" -days 3650 -nodes

# ========= 启动 =========
if command -v systemctl >/dev/null; then

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

# ========= 检测 =========
echo "🔍 检测服务状态..."

sleep 2

# 1. 进程检测
if pgrep -f tuic-server >/dev/null; then
  echo "✅ 进程运行正常"
else
  echo "❌ TUIC 未运行"
  exit 1
fi

# 2. 端口检测
if ss -lunp | grep ${PORT} >/dev/null; then
  echo "✅ 端口监听正常"
else
  echo "❌ 端口未监听"
  exit 1
fi

# 3. systemd 状态
if command -v systemctl >/dev/null; then
  systemctl is-active --quiet tuic && echo "✅ systemd 正常"
fi

# ========= IP =========
IPV4=$(curl -s4 ip.sb || true)
IPV6=$(curl -s6 ip.sb || true)

# ========= 输出 =========
echo ""
echo "====== 节点信息 ======"

if [ -n "$IPV4" ]; then
echo "tuic://${UUID}:${PASS}@${IPV4}:${PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC-${IPV4}"
fi

if [ -n "$IPV6" ]; then
echo "tuic://${UUID}:${PASS}@[${IPV6}]:${PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=www.bing.com#TUIC-${IPV6}"
fi
