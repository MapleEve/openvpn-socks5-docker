# SOCKS5 UDP 代理指南

[English](UDP_GUIDE.md) | 中文

本指南介绍如何通过 sing-box SOCKS5 代理使用 UDP 流量转发。

## UDP 支持概述

sing-box 通过 SOCKS5 UDP ASSOCIATE 机制提供完整的 UDP 代理支持。这允许 UDP 流量（如 DNS 查询、游戏流量、VoIP）通过 SOCKS5 代理隧道转发。

## 工作原理

### SOCKS5 UDP ASSOCIATE 流程

1. **客户端请求**：客户端向 SOCKS5 服务器发送 UDP ASSOCIATE 请求
2. **服务器响应**：服务器分配一个 UDP 中继端口并返回给客户端
3. **UDP 中继**：客户端将 UDP 数据包发送到中继端口
4. **转发**：服务器通过 VPN 隧道转发 UDP 数据包

### 端口范围配置

为了支持多个并发 UDP 会话，我们使用 Linux 临时端口范围：

```yaml
ports:
  - "32768-60999:32768-60999/udp"  # Linux 临时端口范围
```

这个范围基于：
- Linux 默认临时端口：`/proc/sys/net/ipv4/ip_local_port_range`
- 标准范围：32768-60999
- 提供约 28,000 个可用端口用于 UDP 中继

## 客户端配置

### 使用 curl 进行 UDP over SOCKS5

```bash
# DNS 查询通过 SOCKS5（使用 socks5h:// 进行远程 DNS 解析）
curl -x socks5h://username:password@127.0.0.1:18080 https://example.com
```

### 应用程序特定配置

#### 1. 游戏应用
许多游戏使用 UDP 进行低延迟通信。配置您的游戏使用：
- SOCKS5 服务器：`127.0.0.1`
- 端口：`18080`
- 启用 UDP 中继（如果选项可用）

#### 2. VoIP 应用（Discord、TeamSpeak）
VoIP 应用通常使用 UDP 进行语音流量：
- 在应用的代理设置中配置 SOCKS5
- 确保 UDP 选项已启用
- 某些应用可能需要额外的 STUN/TURN 配置

#### 3. DNS 工具
```bash
# 使用 dig 通过 SOCKS5 代理
# 注意：dig 本身不支持 SOCKS5，使用 proxychains 或类似工具
proxychains dig @8.8.8.8 example.com
```

## 测试 UDP 功能

### 基本 UDP 测试

1. **检查 UDP 端口映射**：
```bash
docker-compose ps
# 验证 UDP 端口范围已映射
```

2. **容器内测试 UDP**：
```bash
# 进入容器
docker-compose exec ovpn_singbox_proxy sh

# 测试 UDP DNS 查询
nslookup google.com 8.8.8.8

# 检查 UDP 流量通过 tun0
tcpdump -i tun0 -n udp
```

3. **从主机测试 UDP 代理**：
```bash
# 某些支持 SOCKS5 UDP 的应用
# 示例：带 netcat 的 UDP echo 测试
echo "test" | nc -u -x 127.0.0.1:18080 example.com 7
```

### 高级 UDP 测试

#### 使用 Python 进行 UDP 测试
```python
import socks
import socket

# 配置 SOCKS5 代理
socks.set_default_proxy(
    socks.SOCKS5, 
    "127.0.0.1", 
    18080,
    username="your_username",
    password="your_password"
)
socket.socket = socks.socksocket

# 创建 UDP socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

# 发送 UDP 数据包
sock.sendto(b"Hello UDP", ("example.com", 7))
```

## 故障排除

### 常见 UDP 问题

#### 1. UDP 流量未转发
**原因**：客户端不支持 SOCKS5 UDP ASSOCIATE  
**解决方案**：使用支持正确 SOCKS5 UDP 的客户端

#### 2. UDP 端口不可达
**原因**：Docker 端口映射不正确  
**解决方案**：验证 docker-compose.yml 中的 UDP 端口：
```yaml
ports:
  - "32768-60999:32768-60999/udp"
```

#### 3. 游戏/VoIP 延迟高
**原因**：UDP 数据包路由通过 TCP VPN 隧道  
**解决方案**：
- 确保 OpenVPN 使用 `proto udp` 而非 `proto tcp`
- 检查 VPN 服务器延迟
- 考虑使用更近的 VPN 服务器

#### 4. DNS 解析失败
**原因**：DNS 查询未通过代理  
**解决方案**：使用 `socks5h://` 而非 `socks5://` 进行远程 DNS 解析

### 监控 UDP 流量

```bash
# 监控容器中的 UDP 流量
docker-compose exec ovpn_singbox_proxy sh -c "tcpdump -i any -n udp"

# 检查 sing-box UDP 统计
docker-compose exec ovpn_singbox_proxy sh -c "netstat -anu"

# 查看 UDP 中继端口
docker-compose exec ovpn_singbox_proxy sh -c "ss -anu | grep 18080"
```

## 性能优化

### UDP 缓冲区大小
对于高吞吐量 UDP 应用，考虑调整缓冲区大小：

```bash
# 在容器中
sysctl -w net.core.rmem_default=262144
sysctl -w net.core.wmem_default=262144
```

### 端口范围优化
如果您需要更多并发 UDP 会话，可以扩展端口范围：

```yaml
# docker-compose.yml
ports:
  - "20000-65000:20000-65000/udp"  # 扩展范围
```

## 安全考虑

1. **端口暴露**：大范围 UDP 端口增加了攻击面
2. **防火墙规则**：考虑限制 UDP 端口访问到特定 IP
3. **速率限制**：在生产环境中实施 UDP 速率限制
4. **监控**：定期监控异常 UDP 流量模式

## 兼容性说明

### 支持的应用
- ✅ 原生支持 SOCKS5 UDP 的应用
- ✅ 使用 proxychains-ng 的应用
- ✅ 支持 tun2socks 的应用

### 受限应用
- ⚠️ 仅 TCP 的 SOCKS5 客户端
- ⚠️ 硬编码 DNS 服务器的应用
- ❌ 需要原始套接字的应用

## 配置示例

### 完整的支持 UDP 的 docker-compose.yml
```yaml
services:
  ovpn_singbox_proxy:
    ports:
      - "18080:18080"       # SOCKS5 TCP
      - "18080:18080/udp"   # SOCKS5 UDP
      - "32768-60999:32768-60999/udp"  # UDP 中继范围
    environment:
      - ENABLE_UDP=true
```

### sing-box UDP 配置
`conf/server.json` 中的配置确保 UDP 支持：
```json
{
  "inbounds": [{
    "type": "socks",
    "listen": "::",
    "listen_port": 18080,
    "udp_enable": true,
    "udp_timeout": 300
  }]
}
```

---

有关更多高级配置和故障排除，请参考 [sing-box 文档](https://sing-box.sagernet.org/)。