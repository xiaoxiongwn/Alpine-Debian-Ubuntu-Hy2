#!/usr/bin/env bash

set -e

TUIC_DIR="/etc/tuic"
TUIC_BIN="/usr/local/bin/tuic"
SERVICE_FILE="/etc/systemd/system/tuic.service"
OPENRC_FILE="/etc/init.d/tuic"

red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

detect_system() {

if [ -f /etc/alpine-release ]; then
SYS="alpine"
elif grep -qi debian /etc/os-release; then
SYS="debian"
elif grep -qi ubuntu /etc/os-release; then
SYS="ubuntu"
else
red "不支持的系统"
exit 1
fi

}

install_base() {

if [ "$SYS" = "alpine" ]; then
apk add curl openssl
else
apt update
apt install -y curl openssl
fi

}

download_tuic() {

ARCH=$(uname -m)

case $ARCH in
x86_64) ARCH="x86_64" ;;
aarch64) ARCH="aarch64" ;;
*) red "不支持架构"; exit 1 ;;
esac

URL=$(curl -s https://api.github.com/repos/Itsusinn/tuic/releases/latest \
| grep browser_download_url \
| grep linux-$ARCH \
| cut -d '"' -f4)

curl -L $URL -o /usr/local/bin/tuic
chmod +x /usr/local/bin/tuic

}

gen_cert() {

mkdir -p $TUIC_DIR

openssl req -x509 -nodes -newkey rsa:2048 \
-keyout $TUIC_DIR/server.key \
-out $TUIC_DIR/server.crt \
-days 3650 \
-subj "/CN=tuic"

}

gen_config() {

UUID=$(cat /proc/sys/kernel/random/uuid)

cat > $TUIC_DIR/config.json <<EOF
{
 "server": "[::]:$PORT",
 "users": {
   "$UUID": "passwd"
 },
 "certificate": "$TUIC_DIR/server.crt",
 "private_key": "$TUIC_DIR/server.key",
 "congestion_control": "bbr",
 "alpn": ["h3"],
 "udp_relay_ipv6": true,
 "zero_rtt_handshake": false
}
EOF

}

create_service() {

if [ "$SYS" = "alpine" ]; then

cat > $OPENRC_FILE <<EOF
#!/sbin/openrc-run

command="$TUIC_BIN"
command_args="-c $TUIC_DIR/config.json"
command_background=true
pidfile=/run/tuic.pid
EOF

chmod +x $OPENRC_FILE
rc-update add tuic default
rc-service tuic start

else

cat > $SERVICE_FILE <<EOF
[Unit]
Description=TUIC Server
After=network.target

[Service]
ExecStart=$TUIC_BIN -c $TUIC_DIR/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tuic
systemctl restart tuic

fi

}

show_links() {

IPV4=$(curl -s ipv4.icanhazip.com)
IPV6=$(curl -s -6 icanhazip.com || true)

UUID=$(grep -oP '"\K[^"]+(?=":)' $TUIC_DIR/config.json)

echo
green "=========== TUIC 信息 ==========="
echo "端口: $PORT"
echo "UUID: $UUID"
echo

echo "v2rayN IPv4:"
echo "tuic://$UUID:passwd@$IPV4:$PORT?congestion_control=bbr&udp_relay_mode=native#tuic-ipv4"

if [ -n "$IPV6" ]; then
echo
echo "v2rayN IPv6:"
echo "tuic://$UUID:passwd@[$IPV6]:$PORT?congestion_control=bbr#tuic-ipv6"
fi

echo
green "=========== Clash Meta =========="

cat <<EOF

- name: tuic
  type: tuic
  server: $IPV4
  port: $PORT
  uuid: $UUID
  password: passwd
  udp: true
  congestion-controller: bbr

EOF

}

install_tuic() {

read -p "输入端口 (默认443): " PORT
PORT=${PORT:-443}

install_base
download_tuic
gen_cert
gen_config
create_service
show_links

green "TUIC 安装完成"

}

update_tuic() {

systemctl stop tuic 2>/dev/null || rc-service tuic stop
download_tuic
systemctl start tuic 2>/dev/null || rc-service tuic start

green "更新完成"

}

uninstall_tuic() {

systemctl stop tuic 2>/dev/null || rc-service tuic stop

rm -rf $TUIC_DIR
rm -f $TUIC_BIN
rm -f $SERVICE_FILE
rm -f $OPENRC_FILE

green "卸载完成"

}

menu() {

clear

echo "============================"
echo " TUIC 一键脚本"
echo "============================"
echo "1. 安装 TUIC"
echo "2. 更新 TUIC"
echo "3. 卸载 TUIC"
echo "0. 退出"
echo
read -p "选择: " num

case "$num" in
1) install_tuic ;;
2) update_tuic ;;
3) uninstall_tuic ;;
0) exit ;;
*) red "输入错误" ;;
esac

}

detect_system
menu