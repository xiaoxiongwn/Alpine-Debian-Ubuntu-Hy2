#!/usr/bin/env bash
set -e

### ===== 基本参数 =====
PORT=$(( ( RANDOM % 40000 ) + 20000 ))
UUID=$(cat /proc/sys/kernel/random/uuid)
PASS=$(openssl rand -base64 12)
WORKDIR="/usr/local/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
SERVICE="/etc/systemd/system/xray.service"

echo "=============================="
echo " Xray HY2 一键安装开始"
echo "=============================="

# 安装依赖
apt update -y
apt install -y curl wget unzip openssl

# 下载 Xray 26.3.27
echo ">>> 下载 Xray..."
wget -O xray.zip https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip

unzip -o xray.zip
install -m 755 xray $XRAY_BIN

mkdir -p $WORKDIR

# 生成证书
echo ">>> 生成自签证书..."
openssl req -x509 -nodes -days 3650 \
-newkey rsa:2048 \
-keyout $WORKDIR/private.key \
-out $WORKDIR/cert.crt \
-subj "/CN=www.bing.com"

# 写入配置
echo ">>> 写入配置..."
cat > $WORKDIR/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "password": "$PASS"
        }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$WORKDIR/cert.crt",
        "key_path": "$WORKDIR/private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "freedom"
    }
  ]
}
EOF

# systemd 服务
echo ">>> 创建服务..."
cat > $SERVICE <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=$XRAY_BIN run -config $WORKDIR/config.json
Restart=always
User=root
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

# 启动
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 防火墙
ufw allow $PORT/udp || true
iptables -I INPUT -p udp --dport $PORT -j ACCEPT || true

echo "=============================="
echo "    ✅ 安装完成"
echo "=============================="
echo ""
echo "端口: $PORT"
echo "密码: $PASS"
echo ""
echo "分享链接："
echo "hy2://$PASS@$(curl -s ip.sb):$PORT?sni=www.bing.com&alpn=h3#Xray-HY2"
echo ""