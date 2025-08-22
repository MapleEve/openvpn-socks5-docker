# OpenVPN + SOCKS5 代理 (sing-box 分支)

[English](README.md) | 中文

基于 [sing-box](https://github.com/SagerNet/sing-box) 的轻量级 Docker SOCKS5 代理服务器，所有流量通过 OpenVPN 连接隧道转发。

## 概述

本分支使用 **sing-box v1.10.7** 作为 SOCKS5 代理实现，提供现代高效的代理解决方案，支持流量嗅探和 DNS 解析处理等高级功能。

### 功能特性

- ✅ **现代 SOCKS5 代理**：使用 sing-box 实现高性能代理功能
- ✅ **OpenVPN 集成**：自动连接和隧道建立
- ✅ **桥接网络**：自定义 Docker 网络 (172.20.0.0/24) 避免 DNS 冲突
- ✅ **无 FakeIP 问题**：解决了某些实现中的 DNS 解析问题
- ✅ **流量嗅探**：高级流量分析和路由功能
- ✅ **轻量级**：基于 Alpine Linux 实现最小容器体积
- ✅ **自动重启**：服务监控和自动恢复
- ✅ **UDP 支持**：完整的 UDP 中继支持（[查看 UDP 指南](docs/UDP_GUIDE_CN.md)）

## 快速开始

### 1. 配置 OpenVPN

将您的 OpenVPN 文件放在 `ovpn/` 目录：
- `ovpn/config.ovpn` - OpenVPN 配置文件
- `ovpn/ca.crt` - 证书颁发机构文件
- `ovpn/ta.key` - TLS 认证密钥

### 2. 配置环境变量

复制并编辑环境文件：
```bash
cp .env.example .env
# 编辑 .env 文件，填入您的 VPN 凭据
```

### 3. 使用桥接网络部署

```bash
# 使用桥接网络配置以避免 DNS 冲突
docker-compose up -d
```

您的 SOCKS5 代理将在 `127.0.0.1:18080` 可用。

## 配置说明

### 环境变量

| 变量 | 必需 | 默认值 | 描述 |
|----------|----------|---------|-------------|
| `OPENVPN_CONFIG_FILE` | 是 | `/config/config.ovpn` | 容器内 OpenVPN 配置路径 |
| `OPENVPN_USERNAME` | 否 | - | OpenVPN 用户名（如需认证）|
| `OPENVPN_PASSWORD` | 否 | - | OpenVPN 密码（如需认证）|
| `SOCKS_PORT` | 否 | `18080` | SOCKS5 代理监听端口 |
| `SOCKS5_USERNAME` | 否 | - | SOCKS5 代理用户名（客户端认证）|
| `SOCKS5_PASSWORD` | 否 | - | SOCKS5 代理密码（客户端认证）|
| `ENABLE_UDP` | 否 | `true` | 启用 UDP 中继支持 |
| `USE_HOST_NETWORK` | 否 | `false` | 使用主机网络模式 |
| `TZ` | 否 | `UTC` | 容器时区 |

### sing-box 配置

sing-box 配置从模板 `conf/server.json` 自动生成。主要特性：

- **DNS 解析**：使用 Cloudflare (1.1.1.1) 作为主 DNS
- **无 FakeIP**：禁用以防止 DNS 解析冲突
- **流量嗅探**：启用以做出更好的路由决策
- **桥接网络兼容**：与自定义 Docker 网络配合工作

### 网络架构

```
客户端应用 → SOCKS5 代理 (sing-box) → OpenVPN 隧道 → VPN 服务器 → 互联网
            端口 18080              tun0 接口
```

## 技术细节

### sing-box vs Dante 对比

本分支使用 **sing-box** 而非 dante-server 的几个优势：

| 功能 | sing-box | Dante |
|---------|----------|--------|
| UDP 支持 | ✅ 完整 | ⚠️ Alpine 中受限 |
| DNS 处理 | ✅ 高级 | ❌ 基础 |
| 性能 | ✅ 高 | ✅ 好 |
| 配置 | ✅ JSON | ❌ 复杂 |
| 二进制大小 | ✅ ~15MB | ✅ ~2MB |
| FakeIP 问题 | ✅ 已解决 | ❌ 有问题 |

### 桥接网络

`docker-compose.yml` 使用自定义桥接网络 `172.20.0.0/24` 以：
- 避免与 FakeIP DNS 范围 (198.18.x.x) 冲突
- 提供一致的内部网络
- 通过 VPN 隧道启用正确的 DNS 解析

## 测试

### 基本连接测试
```bash
# 测试 SOCKS5 连接
curl -x socks5://127.0.0.1:18080 https://httpbin.org/ip

# 应返回您的 VPN 出口 IP，而非真实 IP
```

### 高级测试
```bash
# 不使用代理测试（您的真实 IP）
curl https://httpbin.org/ip

# 使用代理测试（VPN IP）
curl -x socks5://127.0.0.1:18080 https://httpbin.org/ip

# 通过代理测试 DNS 解析
curl -x socks5h://127.0.0.1:18080 https://httpbin.org/ip
```

### 容器健康检查
```bash
# 检查容器状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 检查 sing-box 状态
docker-compose exec ovpn_singbox_proxy ps aux | grep sing-box
```

## 故障排除

### 常见问题

#### 1. "No OpenVPN config. Exiting."
**解决方案**：确保 OpenVPN 配置文件存在：
```bash
ls -la ovpn/
# 应显示：config.ovpn, ca.crt, ta.key
```

#### 2. DNS 解析问题
**解决方案**：桥接网络配置应解决 FakeIP 冲突。如果问题持续：
```bash
# 在容器中检查 DNS 配置
docker-compose exec ovpn_singbox_proxy nslookup google.com
```

#### 3. VPN 连接失败
**解决方案**：检查 OpenVPN 凭据和配置：
```bash
# 查看 OpenVPN 日志
docker-compose logs ovpn_singbox_proxy | grep -i openvpn
```

#### 4. SOCKS5 连接被拒绝
**解决方案**：验证 sing-box 正在运行：
```bash
# 检查 sing-box 进程是否活动
docker-compose exec ovpn_singbox_proxy netstat -tlnp | grep 18080
```

### 网络调试

```bash
# 检查 VPN 隧道状态
docker-compose exec ovpn_singbox_proxy ip addr show tun0

# 检查路由表
docker-compose exec ovpn_singbox_proxy ip route

# 测试内部连接
docker-compose exec ovpn_singbox_proxy curl https://httpbin.org/ip
```

## 客户端配置

### 🔴 重要提示：浏览器 SOCKS5 认证问题
大多数浏览器不支持带认证的 SOCKS5 代理。您需要一个本地 HTTP 代理中继。

### 方案 1：Clash Mihomo（推荐）

创建专用的 HTTP 监听器与 SOCKS5 上游：

```yaml
# ~/.config/mihomo/config.yaml
proxies:
  - name: "openvpn-socks5"
    type: socks5
    server: 127.0.0.1
    port: 18080
    username: your_username
    password: your_password

listeners:
  - name: openvpn-http
    type: http
    port: 8890  # 专用 HTTP 端口（避免默认的 7890）
    listen: 127.0.0.1
    proxy: openvpn-socks5  # 所有流量直接转发到 SOCKS5 上游
```

**浏览器设置**：
1. 安装 Zero Omega 扩展
2. 创建 HTTP 代理配置：`127.0.0.1:8890`
**注意**：这创建了一个独立的 HTTP 代理端口，不影响其他 Mihomo 配置

### 方案 2：Surge Mac

使用 IN-PORT 规则路由特定端口流量：

```ini
[Proxy]
OpenVPN-SOCKS = socks5, 127.0.0.1, 18080, username, password

[General]
http-listen = 0.0.0.0:6152, 0.0.0.0:8891  # 监听多个端口

[Rule]
IN-PORT,8891,OpenVPN-SOCKS  # 端口 8891 流量走 OpenVPN-SOCKS
FINAL,DIRECT  # 其他流量直连
```

**浏览器设置**：
1. 安装 Zero Omega 扩展
2. 创建 HTTP 代理配置：`127.0.0.1:8891`

### 方案 3：直接 SOCKS5（支持认证的 Firefox/Edge）

对于支持 SOCKS5 认证的浏览器（Firefox、Edge）：

1. 安装 Zero Omega 扩展
2. 创建新的代理配置：
   - 协议：SOCKS5
   - 服务器：127.0.0.1
   - 端口：18080
   - 用户名：your_username
   - 密码：your_password

**注意**：Chrome 不支持 SOCKS5 认证，请使用方案 1 或 2

### 直接 SOCKS5 使用（支持认证的应用）

- **服务器**：127.0.0.1
- **端口**：18080
- **用户名**：your_socks_username
- **密码**：your_socks_password

### 命令行使用

```bash
# 使用 curl（支持 SOCKS5 认证）
curl -x socks5://username:password@127.0.0.1:18080 https://example.com

# 使用 ssh
ssh -o ProxyCommand='nc -x 127.0.0.1:18080 -X 5 -P username:password %h %p' user@server
```

## 开发

### 从源码构建

```bash
# 构建容器
docker-compose build

# 构建并运行
docker-compose up --build -d
```

### 修改 sing-box 配置

编辑 `conf/server.json` 以自定义：
- DNS 服务器
- 路由规则
- 嗅探选项
- 日志级别

### 文件结构

```
.
├── Dockerfile                      # 容器构建指令
├── docker-compose.yml              # 生产部署
├── entrypoint.sh                   # 容器启动脚本
├── conf/
│   └── server.json                  # 服务器配置
├── scripts/
│   └── openvpn_up.sh               # OpenVPN 连接脚本
├── ovpn/
│   ├── *.example                   # OpenVPN 示例文件
│   └── [您的实际文件]                # 在此放置真实配置
├── docs/
│   └── UDP_GUIDE_CN.md             # UDP 代理文档
└── README_CN.md                     # 本文件
```

---

## 许可证

查看 LICENSE 文件了解详情。

**分支**：sing-box  
**sing-box 版本**：v1.10.7  
**最后更新**：2025-08-22