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
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/tuic/main/tuic.sh) install
```

---

## 🗑 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/tuic/main/tuic.sh) uninstall
```

---

## ✨ 功能

* 自动安装 TUIC
* 自动生成证书（[www.bing.com）](http://www.bing.com）)
* 自动开机启动
* 输出 v2rayN IPv4 / IPv6 链接
* 支持 systemd / openrc

---

## ⚠️ 注意

* 默认端口随机
* 防火墙请放行 UDP 端口
* 自签证书需 allowInsecure=true
