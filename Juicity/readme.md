# 🚀 Juicity 一键脚本（由Ai生成）

支持系统：Alpine / Debian / Ubuntu

支持架构：x86_64 / ARM64

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/a88wyzz/Alpine-Debian-Ubuntu-Hy2/main/Juicity/juicity.sh)

```
---
Juicity是一个基于quic的代理协议和实现，其灵感来自TUIC： https://github.com/juicity/juicity

客户端推荐使用Throne(基于sing-box)，支持导入Juicity节点链接： https://github.com/throneproj/Throne

# ✨ 功能

* 安装 Juicity
* 自动生成bing自签证书
* 自动设置开机启动
* 输出 IPv4 / IPv6 节点链接
* 支持 systemd / openrc 进程监视守护

# ⚠️ 注意

* Juicity使用UDP端口
* 自签证书需允许不安全
