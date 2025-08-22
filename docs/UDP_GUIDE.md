# SOCKS5 UDP Proxy Guide

English | [中文](UDP_GUIDE_CN.md)

This guide explains how to use UDP traffic forwarding through the sing-box SOCKS5 proxy.

> **⚠️ Important**: UDP support requires host network mode. When `ENABLE_UDP=true` is set, the container automatically forces `USE_HOST_NETWORK=true` to handle the large UDP port range (32768-60999) required for UDP ASSOCIATE.

## UDP Support Overview

sing-box provides full UDP proxy support through the SOCKS5 UDP ASSOCIATE mechanism. This allows UDP traffic (such as DNS queries, gaming traffic, VoIP) to be forwarded through the SOCKS5 proxy tunnel.

## How It Works

### SOCKS5 UDP ASSOCIATE Flow

1. **Client Request**: Client sends UDP ASSOCIATE request to SOCKS5 server
2. **Server Response**: Server allocates a UDP relay port and returns it to client
3. **UDP Relay**: Client sends UDP packets to the relay port
4. **Forwarding**: Server forwards UDP packets through the VPN tunnel

### Port Range Configuration

To support multiple concurrent UDP sessions, we use the Linux ephemeral port range:

```yaml
ports:
  - "32768-60999:32768-60999/udp"  # Linux ephemeral port range
```

This range is based on:
- Linux default ephemeral ports: `/proc/sys/net/ipv4/ip_local_port_range`
- Standard range: 32768-60999
- Provides ~28,000 available ports for UDP relay

## Client Configuration

### Using curl with UDP over SOCKS5

```bash
# DNS queries through SOCKS5 (use socks5h:// for remote DNS resolution)
curl -x socks5h://username:password@127.0.0.1:18080 https://example.com
```

### Application-Specific Configuration

#### 1. Gaming Applications
Many games use UDP for low-latency communication. Configure your game to use:
- SOCKS5 Server: `127.0.0.1`
- Port: `18080`
- Enable UDP relay (if option available)

#### 2. VoIP Applications (Discord, TeamSpeak)
VoIP applications typically use UDP for voice traffic:
- Configure SOCKS5 in the app's proxy settings
- Ensure UDP option is enabled
- Some apps may require additional STUN/TURN configuration

#### 3. DNS Tools
```bash
# Using dig through SOCKS5 proxy
# Note: dig doesn't natively support SOCKS5, use proxychains or similar
proxychains dig @8.8.8.8 example.com
```

## Testing UDP Functionality

### Basic UDP Testing

1. **Check UDP Port Mapping**:
```bash
docker-compose ps
# Verify UDP port range is mapped
```

2. **Test UDP Inside Container**:
```bash
# Enter the container
docker-compose exec ovpn_singbox_proxy sh

# Test UDP DNS query
nslookup google.com 8.8.8.8

# Check UDP traffic goes through tun0
tcpdump -i tun0 -n udp
```

3. **Test UDP Proxy from Host**:
```bash
# Some applications that support SOCKS5 UDP
# Example: UDP echo test with netcat
echo "test" | nc -u -x 127.0.0.1:18080 example.com 7
```

### Advanced UDP Testing

#### UDP Testing with Python
```python
import socks
import socket

# Configure SOCKS5 proxy
socks.set_default_proxy(
    socks.SOCKS5, 
    "127.0.0.1", 
    18080,
    username="your_username",
    password="your_password"
)
socket.socket = socks.socksocket

# Create UDP socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

# Send UDP packet
sock.sendto(b"Hello UDP", ("example.com", 7))
```

## Troubleshooting

### Common UDP Issues

#### 1. UDP Traffic Not Forwarded
**Cause**: Client doesn't support SOCKS5 UDP ASSOCIATE  
**Solution**: Use a client with proper SOCKS5 UDP support

#### 2. UDP Ports Unreachable
**Cause**: Docker port mapping incorrect  
**Solution**: Verify UDP ports in docker-compose.yml:
```yaml
ports:
  - "32768-60999:32768-60999/udp"
```

#### 3. High Latency in Games/VoIP
**Cause**: UDP packets routed through TCP VPN tunnel  
**Solution**:
- Ensure OpenVPN uses `proto udp` not `proto tcp`
- Check VPN server latency
- Consider using a closer VPN server

#### 4. DNS Resolution Failures
**Cause**: DNS queries not going through proxy  
**Solution**: Use `socks5h://` instead of `socks5://` for remote DNS resolution

### Monitoring UDP Traffic

```bash
# Monitor UDP traffic in container
docker-compose exec ovpn_singbox_proxy sh -c "tcpdump -i any -n udp"

# Check sing-box UDP statistics
docker-compose exec ovpn_singbox_proxy sh -c "netstat -anu"

# View UDP relay ports
docker-compose exec ovpn_singbox_proxy sh -c "ss -anu | grep 18080"
```

## Performance Optimization

### UDP Buffer Sizes
For high-throughput UDP applications, consider adjusting buffer sizes:

```bash
# Inside container
sysctl -w net.core.rmem_default=262144
sysctl -w net.core.wmem_default=262144
```

### Port Range Optimization
If you need more concurrent UDP sessions, expand the port range:

```yaml
# docker-compose.yml
ports:
  - "20000-65000:20000-65000/udp"  # Extended range
```

## Security Considerations

1. **Port Exposure**: Large UDP port ranges increase attack surface
2. **Firewall Rules**: Consider restricting UDP port access to specific IPs
3. **Rate Limiting**: Implement UDP rate limiting in production
4. **Monitoring**: Regularly monitor for unusual UDP traffic patterns

## Compatibility Notes

### Supported Applications
- ✅ Applications with native SOCKS5 UDP support
- ✅ Applications using proxychains-ng
- ✅ Applications supporting tun2socks

### Limited Applications
- ⚠️ TCP-only SOCKS5 clients
- ⚠️ Applications with hardcoded DNS servers
- ❌ Applications requiring raw sockets

## Configuration Examples

### Complete UDP-Enabled docker-compose.yml
```yaml
services:
  ovpn_singbox_proxy:
    ports:
      - "18080:18080"       # SOCKS5 TCP
      - "18080:18080/udp"   # SOCKS5 UDP
      - "32768-60999:32768-60999/udp"  # UDP relay range
    environment:
      - ENABLE_UDP=true
```

### sing-box UDP Configuration
Configuration in `conf/server.json` ensures UDP support:
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

For more advanced configuration and troubleshooting, refer to the [sing-box documentation](https://sing-box.sagernet.org/).