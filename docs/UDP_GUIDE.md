# sing-box SOCKS5 UDP代理说明

## UDP工作原理

sing-box的SOCKS5 UDP代理采用标准的SOCKS5 UDP ASSOCIATE机制：

1. **TCP控制连接**：客户端首先建立TCP连接到SOCKS5端口（默认18080）
2. **UDP ASSOCIATE请求**：通过TCP连接发送UDP关联请求
3. **动态端口分配**：sing-box动态分配一个UDP中继端口并返回给客户端
4. **UDP数据传输**：客户端向分配的UDP端口发送封装的UDP数据包

## 端口配置

### 当前配置
```yaml
ports:
  - "18080:18080"       # SOCKS5 TCP控制端口
  - "18080:18080/udp"   # SOCKS5 UDP（可选）
  - "32768-60999:32768-60999/udp"  # Linux临时端口范围（UDP中继）
```

### 重要说明

- **sing-box v1.10.7不支持配置UDP端口范围**
- UDP中继端口由Linux内核从临时端口范围动态分配
- 端口分配不是1:1映射（不使用客户端请求的端口）
- **Linux临时端口范围**: 32768-60999 （可通过 `/proc/sys/net/ipv4/ip_local_port_range` 查看）

## 网络模式选择

### Bridge模式（当前）
- 优点：网络隔离性好，安全
- 缺点：需要端口映射，UDP端口可能无法预测

### Host模式（推荐用于生产环境）
如果需要完整的UDP支持，建议使用host网络模式：

```yaml
# docker-compose.host.yml
services:
  ovpn_singbox_proxy:
    network_mode: host
    environment:
      - USE_HOST_NETWORK=true
    # 不需要ports映射
```

## 测试结果

### 功能测试 ✅
- TCP代理：正常工作
- UDP关联：成功建立
- UDP数据传输：正常（DNS查询测试通过）
- 认证机制：按配置正确工作

### 端口分配测试
```
客户端请求端口: 42767
服务器分配端口: 38940
状态: 动态分配（非1:1映射）
端口范围: 32768-60999 (Linux临时端口范围)
```

## 客户端配置示例

### Python SOCKS5 UDP客户端
```python
# 1. 建立TCP控制连接
tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
tcp_sock.connect(("proxy_host", 18080))

# 2. SOCKS5握手和认证
# ...

# 3. 发送UDP ASSOCIATE请求
request = b'\x05\x03\x00\x01'  # UDP关联
request += socket.inet_aton('0.0.0.0')
request += struct.pack('>H', 0)
tcp_sock.send(request)

# 4. 获取分配的UDP中继地址
response = tcp_sock.recv(10)
# 解析response获取UDP中继地址和端口

# 5. 向中继端口发送UDP数据
udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp_sock.sendto(udp_packet, (relay_addr, relay_port))
```

## 建议

1. **开发环境**：使用bridge模式，接受动态端口分配
2. **生产环境**：考虑使用host网络模式避免端口映射问题
3. **防火墙配置**：开放Linux临时端口范围（32768-60999）用于UDP中继

## 已知限制

- sing-box当前版本不支持配置固定的UDP端口范围
- UDP端口不能保证1:1映射
- 在NAT环境下可能需要额外配置