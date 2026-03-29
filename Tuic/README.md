# TUIC 一键脚本（通用 VPS）

支持系统：

* Alpine
* Debian / Ubuntu

支持架构：

* x86_64
* ARM64

---

## 🚀 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/a88wyzz/Alpine-Debian-Ubuntu-Hy2/main/Tuic/tuic.sh)
```

---

## 🗑 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/a88wyzz/Alpine-Debian-Ubuntu-Hy2/main/Tuic/tuic.sh) uninstall
```

---

## ✨ 功能

* 自动安装 TUIC
* 自动生自签证书（[www.bing.com）](http://www.bing.com）)
* 自动开机启动
* 输出 v2rayN IPv4 / IPv6 链接
* 支持 systemd / openrc 进程监视守护

---

## ⚠️ 注意

* 默认端口随机，可自行更改，配置文件路径 /usr/local/tuic/config.yaml
* 更改端口后使用命令 service tuic restart 生效 
* VPS防火墙请放行 UDP 端口
* 自签证书需允许不安全 allowInsecure=true
