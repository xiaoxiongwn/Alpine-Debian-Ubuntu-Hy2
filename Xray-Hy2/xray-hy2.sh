#!/usr/bin/env bash
set -e

WORKDIR="/usr/local/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
SERVICE="/etc/systemd/system/xray.service"

green() { echo -e "\033[32m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

install_xray() {
    green ">>> 开始安装 Xray + HY2"

    PORT=$(( ( RANDOM % 40000 ) + 20000 ))
    PASS=$(openssl rand -hex 8)

    apt update -y
    apt install -y curl wget unzip openssl

    cd /tmp
    wget -O xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
    unzip -o xray.zip
    install -m 755 xray $XRAY_BIN

    mkdir -p $WORKDIR

    green ">>> 生成证书"
    openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout $WORKDIR/private.key \
    -out $WORKDIR/cert.crt \
    -subj "/CN=www.bing.com"
    
    green ">>> 生成证书指纹"
FINGERPRINT=$(openssl x509 -in $WORKDIR/cert.crt -noout -fingerprint -sha256 \
| cut -d "=" -f2 | tr -d ':' | tr 'A-Z' 'a-z')

    green ">>> 写入配置"
    cat > $WORKDIR/config.json <<EOF
{
  "log": { "loglevel": "debug" },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 1081,
      "protocol": "hysteria",
      "settings": {
        "version": 2,
        "clients": [
          {
            "auth": "5783a3e7-e373-51cd-8642-c83782b807c5"
          }
        ]
      },
      "streamSettings": {
        "network": "hysteria",
        "hysteriaSettings": {
          "version": 2
        },
        "security": "tls",
        "tlsSettings": {
          "alpn": ["h3"],
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/cert.crt",
              "keyFile": "/usr/local/etc/xray/private.key"
            }
          ]
        },
        "finalmask": {
          "udp": [
            {
              "type": "salamander",
              "settings": {
                "password": "12345678"
              }
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    green ">>> 创建 systemd 服务"
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

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray

    ufw allow $PORT/udp 2>/dev/null || true
    iptables -I INPUT -p udp --dport $PORT -j ACCEPT 2>/dev/null || true

    IP=$(curl -s ip.sb)

    green "=============================="
    green "      ✅ 安装完成"
    green "=============================="
    echo ""
    echo "端口: $PORT"
    echo "密码: $PASS"
    echo ""
    echo "分享链接："
    echo "hy2://$PASS@$IP:$PORT?sni=www.bing.com&alpn=h3&insecure=1&allowInsecure=1$pinSHA256=$FINGERPRINT#Xray-HY2"
    echo ""
}

uninstall_xray() {
    yellow ">>> 开始卸载"

    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true

    rm -f $SERVICE
    rm -rf $WORKDIR
    rm -f $XRAY_BIN

    systemctl daemon-reload

    red "✅ 已彻底卸载 Xray + HY2"
}

menu() {
    echo "=============================="
    echo " Xray HY2 管理脚本"
    echo "=============================="
    echo "1. 安装 Xray + HY2"
    echo "2. 卸载"
    echo "0. 退出"
    echo "=============================="
    read -p "请选择: " num

    case "$num" in
        1) install_xray ;;
        2) uninstall_xray ;;
        0) exit 0 ;;
        *) red "无效输入" ;;
    esac
}

menu
