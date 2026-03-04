# V2Ray WS+TLS 一键安装管理脚本

基于 [wulabing/V2Ray_ws-tls_bash_onekey](https://github.com/wulabing/V2Ray_ws-tls_bash_onekey) 二次维护，使用自有仓库作为主源以保证长期可用。

当前版本：`1.1.9.0`

---

## 系统要求

| 系统 | 最低版本 |
|------|----------|
| Debian | 9+ |
| Ubuntu | 18.04+ |
| CentOS | 7+ |

- 需要 **root 权限**
- 服务器需已将域名 **A 记录解析至本机 IP**
- 80 / 443 端口未被占用

---

## 快速开始

### 远程一键安装（推荐）

无需提前下载脚本，直接在服务器上运行：

```bash
bash <(curl -L https://raw.githubusercontent.com/vipty/v2ray-setup/main/install.sh) --host your.domain.com --mode ws
```

**命令解析：**

```
bash <(curl -L https://raw.githubusercontent.com/vipty/v2ray-setup/main/install.sh) --host your.domain.com --mode ws
│     │   └─ -L：跟随重定向，自动处理 GitHub 跳转         │                   │
│     └─ 进程替换：将 curl 下载的内容作为脚本文件传给 bash  │                   │
│        等价于先下载到临时文件再执行，但不会在磁盘留文件    │                   │
│                                                          │                   └─ 安装模式：ws = Nginx+WebSocket+TLS
└─ 用 bash 执行下载到的脚本                                 └─ 指定域名，跳过交互式输入
```

| 部分 | 说明 |
|------|------|
| `curl -L <url>` | 从 GitHub 下载 install.sh 脚本内容，`-L` 自动跟随 302 跳转 |
| `bash <(...)` | 进程替换语法，将括号内命令的输出作为文件传给 bash 执行，**脚本不落盘** |
| `--host your.domain.com` | 预设域名，安装时跳过交互输入步骤 |
| `--mode ws` | 直接进入 WS+TLS 安装流程，跳过菜单选择（可选 `ws` 或 `h2`）|

> 将 `your.domain.com` 替换为已解析到本机 IP 的真实域名。

HTTP/2 模式：

```bash
bash <(curl -L https://raw.githubusercontent.com/vipty/v2ray-setup/main/install.sh) --host your.domain.com --mode h2
```

---

### 下载后本地运行

```bash
# 下载脚本
curl -L https://raw.githubusercontent.com/vipty/v2ray-setup/main/install.sh -o install.sh

# 交互菜单模式
bash install.sh

# 非交互模式
bash install.sh --host your.domain.com --mode ws
```

---

## 菜单说明

运行脚本后进入交互菜单，输入对应数字执行操作：

### 安装向导

| 编号 | 功能 |
|------|------|
| 0 | 升级脚本至最新版本 |
| 1 | 安装 V2Ray（Nginx + WebSocket + TLS）**推荐** |
| 2 | 安装 V2Ray（HTTP/2）|
| 3 | 升级 V2Ray core |

### 配置变更

| 编号 | 功能 |
|------|------|
| 4 | 变更 UUID |
| 5 | 变更 alterID |
| 6 | 变更连接端口 |
| 7 | 变更 TLS 版本（仅 ws+tls 模式有效）|
| 18 | 变更 WebSocket 伪装路径 |

### 查看信息

| 编号 | 功能 |
|------|------|
| 8 | 实时访问日志（tail -f）|
| 9 | 实时错误日志（tail -f）|
| 10 | 查看 V2Ray 配置信息及导入链接 |

### 其他选项

| 编号 | 功能 |
|------|------|
| 11 | 安装 BBR 锐速加速脚本（第三方） |
| 12 | 安装 MTProxy（暂不可用）|
| 13 | 手动更新 SSL 证书 |
| 14 | 卸载 V2Ray |
| 15 | 更新证书自动续签 crontab 任务 |
| 16 | 清空证书遗留文件 |
| 17 | 退出 |
| 19 | 内核分析 & 一键启用 BBR 加速 |

---

## 安装流程说明

### WS+TLS 模式（选项 1）

完整安装流程：

1. 检查 root 权限
2. 分析内核并推荐 BBR
3. 安装系统依赖（wget、git、curl、cron 等）
4. 安装 chrony 时间同步（证书申请要求误差 < 3 分钟）
5. 验证域名 DNS 解析与本机 IP 是否匹配
6. 安装 V2Ray（v2fly 官方源）
7. 编译安装 Nginx（含 OpenSSL 1.1.1k + HTTP/2 支持）
8. 申请 Let's Encrypt SSL 证书（EC-256）
9. 生成 vmess 配置及二维码/导入链接
10. 设置证书每周自动续签（cron：每周日凌晨 3 点）

### HTTP/2 模式（选项 2）

与 WS+TLS 类似，但不使用 Nginx 反代，V2Ray 直接监听端口处理 H2 流量。

---

## 客户端配置

安装完成后，配置信息保存在 `~/v2ray_info.inf`，可随时查看：

```
地址（address）:  your.domain.com
端口（port）:     443
用户 ID（UUID）:  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
额外 ID（alterID）: 0
加密方式:          自适应
传输协议:          ws
伪装类型:          none
路径:              /xxxxxxxx/
底层传输安全:      tls
```

### 推荐客户端

| 平台 | 客户端 |
|------|--------|
| Android | V2RayNG |
| Windows | V2RayN |
| iOS | Shadowrocket / Quantumult X |
| macOS | V2RayX / ClashX |
| 路由器 | OpenWrt + V2Ray |

> 导入方式：使用安装完成后显示的 `vmess://` 链接或扫描二维码。

---

## TLS 版本说明

默认安装使用 **TLS 1.3 only**（最高安全性）。

如需兼容旧版客户端，安装完成后通过菜单选项 7 切换：

| 选项 | 适用场景 |
|------|----------|
| TLS 1.3 only（默认） | V2RayNG / V2RayN / Shadowrocket 现代版本 |
| TLS 1.2 + 1.3 | 兼容模式，适合部分旧版客户端 |
| TLS 1.1 + 1.2 + 1.3 | 最大兼容，适合 Quantumult X / 旧版路由器 |

---

## 常见问题

### SSL 证书申请失败

1. 检查服务器时间误差是否超过 3 分钟：`date`
2. 检查域名 DNS 是否已解析至本机 IP
3. 检查 80 端口是否被占用：`lsof -i:80`

### 证书续签

证书每周日凌晨 3 点自动续签，续签脚本位于 `/usr/bin/ssl_update.sh`。

手动触发续签：菜单选项 13。

### 查看服务状态

```bash
systemctl status v2ray
systemctl status nginx
```

### 重启服务

```bash
systemctl restart v2ray
systemctl restart nginx
```

---

## 文件路径参考

| 文件 | 路径 |
|------|------|
| V2Ray 配置 | `/usr/local/etc/v2ray/config.json` |
| Nginx 配置 | `/etc/nginx/conf/conf.d/v2ray.conf` |
| SSL 证书 | `/data/v2ray.crt` |
| SSL 私钥 | `/data/v2ray.key` |
| V2Ray 连接信息 | `~/v2ray_info.inf` |
| vmess 配置（JSON）| `/usr/local/vmess_qr.json` |
| 访问日志 | `/var/log/v2ray/access.log` |
| 错误日志 | `/var/log/v2ray/error.log` |
| 证书续签脚本 | `/usr/bin/ssl_update.sh` |

---

## 卸载

菜单选项 14，或直接运行：

```bash
bash install.sh uninstall
```

卸载过程会询问是否同时删除 Nginx 和 acme.sh 证书。

---

## 脚本更新与推送

修改脚本后需要推送到 GitHub，远程一键安装命令才能使用最新版本。

### 日常推送流程

```bash
cd /Users/amking/python-soft/server-fq

# 查看修改了哪些文件
git status

# 暂存要提交的文件
git add install.sh
git add README.md          # 如果文档也有修改

# 提交（引号内填写本次修改的简要说明）
git commit -m "描述本次修改内容"

# 推送到 GitHub
git push
```

### 推送后验证

推送完成后，确认 GitHub 上已更新（通常 1 分钟内生效）：

```bash
curl -sL https://raw.githubusercontent.com/vipty/v2ray-setup/main/install.sh | grep shell_version=
```

返回的版本号与本地 `install.sh` 中 `shell_version` 一致即说明推送成功，此时可以在服务器上运行安装命令。
