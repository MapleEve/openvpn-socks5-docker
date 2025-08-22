# OpenVPN + SOCKS5 Proxy (sing-box branch)

A lightweight, Docker-based SOCKS5 proxy server using [sing-box](https://github.com/SagerNet/sing-box) that tunnels all traffic through an OpenVPN connection.

## Overview

This branch uses **sing-box v1.10.7** as the SOCKS5 proxy implementation, providing a modern and efficient proxy solution with advanced features like traffic sniffing and DNS resolution handling.

### Features

- ✅ **Modern SOCKS5 Proxy**: Using sing-box for high-performance proxy functionality  
- ✅ **OpenVPN Integration**: Automatic connection and tunnel establishment
- ✅ **Bridge Networking**: Custom Docker network (172.20.0.0/24) to avoid DNS conflicts
- ✅ **No FakeIP Issues**: Resolved DNS resolution problems that affect some implementations
- ✅ **Traffic Sniffing**: Advanced traffic analysis and routing capabilities
- ✅ **Lightweight**: Based on Alpine Linux for minimal container size
- ✅ **Auto-restart**: Service monitoring and automatic recovery
- ✅ **UDP Support**: Full UDP relay support ([see UDP Guide](docs/UDP_GUIDE.md))

## Quick Start

### 1. Setup OpenVPN Configuration

Place your OpenVPN files in the `ovpn/` directory:
- `ovpn/config.ovpn` - Your OpenVPN configuration file
- `ovpn/ca.crt` - Certificate authority file  
- `ovpn/ta.key` - TLS authentication key

### 2. Configure Environment Variables

Copy and edit the environment file:
```bash
cp .env.example .env
# Edit .env with your VPN credentials
```

### 3. Deploy with Bridge Network

```bash
# Use the bridge network configuration to avoid DNS conflicts
docker-compose up -d
```

Your SOCKS5 proxy will be available at `127.0.0.1:1080`.

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENVPN_CONFIG_FILE` | Yes | `/config/config.ovpn` | Path to OpenVPN config inside container |
| `OPENVPN_USERNAME` | Yes* | - | OpenVPN username (*if required by provider) |
| `OPENVPN_PASSWORD` | Yes* | - | OpenVPN password (*if required by provider) |
| `SOCKS_PORT` | No | `1080` | SOCKS5 proxy listening port |

### sing-box Configuration

The sing-box configuration is automatically generated from the template at `conf/server.json`. Key features:

- **DNS Resolution**: Uses Cloudflare (1.1.1.1) as primary DNS
- **No FakeIP**: Disabled to prevent DNS resolution conflicts
- **Traffic Sniffing**: Enabled for better routing decisions
- **Bridge Network Compatible**: Works with custom Docker networks

### Network Architecture

```
Client App → SOCKS5 Proxy (sing-box) → OpenVPN Tunnel → VPN Server → Internet
             Port 1080              tun0 interface
```

## Technical Details

### sing-box vs Dante Comparison

This branch uses **sing-box** instead of dante-server for several advantages:

| Feature | sing-box | Dante |
|---------|----------|--------|
| UDP Support | ✅ Full | ⚠️ Limited in Alpine |
| DNS Handling | ✅ Advanced | ❌ Basic |
| Performance | ✅ High | ✅ Good |
| Configuration | ✅ JSON | ❌ Complex |
| Binary Size | ✅ ~15MB | ✅ ~2MB |
| FakeIP Issues | ✅ Resolved | ❌ Problematic |

### Bridge Network

The `docker-compose.yml` uses a custom bridge network `172.20.0.0/24` to:
- Avoid conflicts with FakeIP DNS ranges (198.18.x.x)
- Provide consistent internal networking
- Enable proper DNS resolution through the VPN tunnel

## Testing

### Basic Connectivity Test
```bash
# Test SOCKS5 connection
curl -x socks5://127.0.0.1:1080 https://httpbin.org/ip

# Should return your VPN exit IP, not your real IP
```

### Advanced Testing
```bash
# Test without proxy (your real IP)
curl https://httpbin.org/ip

# Test with proxy (VPN IP) 
curl -x socks5://127.0.0.1:1080 https://httpbin.org/ip

# Test DNS resolution through proxy
curl -x socks5h://127.0.0.1:1080 https://httpbin.org/ip
```

### Container Health Check
```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f

# Check sing-box status
docker-compose exec ovpn_singbox_proxy ps aux | grep sing-box
```

## Troubleshooting

### Common Issues

#### 1. "No OpenVPN config. Exiting."
**Solution**: Ensure OpenVPN configuration files exist:
```bash
ls -la ovpn/
# Should show: config.ovpn, ca.crt, ta.key
```

#### 2. DNS Resolution Issues
**Solution**: The bridge network configuration should resolve FakeIP conflicts. If issues persist:
```bash
# Check DNS configuration in container
docker-compose exec ovpn_singbox_proxy nslookup google.com
```

#### 3. VPN Connection Fails
**Solution**: Check OpenVPN credentials and configuration:
```bash
# View OpenVPN logs
docker-compose logs ovpn_singbox_proxy | grep -i openvpn
```

#### 4. SOCKS5 Connection Refused
**Solution**: Verify sing-box is running:
```bash
# Check if sing-box process is active
docker-compose exec ovpn_singbox_proxy netstat -tlnp | grep 18080
```

### Network Debugging

```bash
# Check VPN tunnel status
docker-compose exec ovpn_singbox_proxy ip addr show tun0

# Check routing table
docker-compose exec ovpn_singbox_proxy ip route

# Test internal connectivity
docker-compose exec ovpn_singbox_proxy curl https://httpbin.org/ip
```

## Client Configuration

### 🔴 Important: Browser SOCKS5 Authentication Issue
Most browsers don't support authenticated SOCKS5 proxies. You need a local HTTP proxy relay.

### Solution 1: Clash Mihomo (Recommended)

Create a dedicated HTTP listener with SOCKS5 upstream:

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
    port: 8890  # Dedicated HTTP port (avoiding default 7890)
    listen: 127.0.0.1
    proxy: openvpn-socks5  # Direct all traffic to SOCKS5 upstream
```

**Browser Setup**:
1. Install Zero Omega extension
2. Create HTTP proxy profile: `127.0.0.1:8890`
**Note**: This creates an independent HTTP proxy port that doesn't affect other Mihomo configurations

### Solution 2: Surge Mac

Use IN-PORT rule to route specific port traffic:

```ini
[Proxy]
OpenVPN-SOCKS = socks5, 127.0.0.1, 18080, username, password

[General]
http-listen = 0.0.0.0:6152, 0.0.0.0:8891  # Listen on multiple ports

[Rule]
IN-PORT,8891,OpenVPN-SOCKS  # Port 8891 traffic goes to OpenVPN-SOCKS
FINAL,DIRECT  # Other traffic direct
```

**Browser Setup**:
1. Install Zero Omega extension
2. Create HTTP proxy profile: `127.0.0.1:8891`

### Solution 3: Direct SOCKS5 (Firefox/Edge with Authentication Support)

For browsers that support SOCKS5 authentication (Firefox, Edge):

1. Install Zero Omega extension
2. Create new proxy profile:
   - Protocol: SOCKS5
   - Server: 127.0.0.1
   - Port: 18080
   - Username: your_username
   - Password: your_password

**Note**: Chrome doesn't support SOCKS5 authentication, use Solution 1 or 2 instead

### Direct SOCKS5 Usage (for apps that support authentication)

- **Server**: 127.0.0.1
- **Port**: 18080
- **Username**: your_socks_username
- **Password**: your_socks_password

### Command Line Usage

```bash
# With curl (supports SOCKS5 auth)
curl -x socks5://username:password@127.0.0.1:18080 https://example.com

# With ssh
ssh -o ProxyCommand='nc -x 127.0.0.1:18080 -X 5 -P username:password %h %p' user@server
```

## Development

### Building from Source

```bash
# Build the container
docker-compose build

# Run with build
docker-compose up --build -d
```

### Modifying sing-box Configuration

Edit `conf/sing-box-config-template.json` to customize:
- DNS servers
- Routing rules  
- Sniffing options
- Logging levels

### File Structure

```
.
├── Dockerfile                      # Container build instructions
├── docker-compose.yml              # Production deployment
├── entrypoint.sh                   # Container startup script
├── conf/
│   └── server.json                  # Server configuration
├── scripts/
│   └── openvpn_up.sh               # OpenVPN connection script
├── ovpn/
│   ├── *.example                   # Example OpenVPN files
│   └── [your actual files]        # Place real configs here
├── docs/
│   └── UDP_GUIDE.md                # UDP proxy documentation
└── README.md                       # This file
```

---

## License

See LICENSE file for details.

**Branch**: sing-box  
**sing-box Version**: v1.10.7  
**Last Updated**: 2025-08-21