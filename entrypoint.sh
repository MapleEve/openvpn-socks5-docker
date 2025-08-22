#!/bin/sh
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a /logs/entrypoint.log
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a /logs/entrypoint.log
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a /logs/entrypoint.log
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a /logs/entrypoint.log
}

# Initialize log file
mkdir -p /logs
echo "Sing-box OpenVPN SOCKS5 Proxy - $(date)" > /logs/entrypoint.log

# Check if OpenVPN config file exists
if [ ! -f "$OPENVPN_CONFIG_FILE" ]; then
    error "OpenVPN config file not found: $OPENVPN_CONFIG_FILE"
    exit 1
fi

# Ensure TUN device is available
if [ ! -c /dev/net/tun ]; then
    log "Creating TUN device..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 666 /dev/net/tun
fi

# Load TUN module if not already loaded
if ! lsmod | grep -q "^tun"; then
    log "Loading TUN kernel module..."
    modprobe tun || warn "Failed to load TUN module (may not be needed)"
fi

log "Starting OpenVPN SOCKS5 Proxy with sing-box..."

# Create credentials file if username and password are provided
if [ -n "$OPENVPN_USERNAME" ] && [ -n "$OPENVPN_PASSWORD" ]; then
    log "Creating OpenVPN credentials file..."
    echo "$OPENVPN_USERNAME" > /tmp/credentials
    echo "$OPENVPN_PASSWORD" >> /tmp/credentials
    chmod 600 /tmp/credentials
    OPENVPN_AUTH_OPTION="--auth-user-pass /tmp/credentials"
else
    log "No OpenVPN credentials provided, using config file auth"
    OPENVPN_AUTH_OPTION=""
fi

# Function to preprocess OpenVPN configuration (universal approach)
preprocess_ovpn_config() {
    local original_config="$1"
    local processed_config="/tmp/processed_config.ovpn"
    
    log "Preprocessing OpenVPN configuration..."
    
    # Check if original config exists
    if [ ! -f "$original_config" ]; then
        error "OpenVPN config file not found: $original_config"
        return 1
    fi
    
    # Start with original config
    cp "$original_config" "$processed_config"
    
    log "Applying universal OpenVPN configuration fixes..."
    
    # === DEPRECATED OPTIONS REMOVAL (based on official OpenVPN docs) ===
    # Remove/comment all deprecated options that generate warnings
    
    # REMOVED options (will cause errors):
    sed -i '/^no-iv/d' "$processed_config"                          # Removed in 2.5
    sed -i '/^#no-iv/d' "$processed_config"
    sed -i '/^client-cert-not-required/d' "$processed_config"       # Removed in 2.5, use --verify-client-cert none
    sed -i '/^#client-cert-not-required/d' "$processed_config"
    sed -i '/^ifconfig-pool-linear/d' "$processed_config"           # Removed in 2.5
    sed -i '/^#ifconfig-pool-linear/d' "$processed_config"
    sed -i '/^key-method/d' "$processed_config"                     # Removed in 2.5
    sed -i '/^#key-method/d' "$processed_config"
    sed -i '/^tls-remote/d' "$processed_config"                     # Removed in 2.4
    sed -i '/^#tls-remote/d' "$processed_config"
    sed -i '/^compat-names/d' "$processed_config"                   # Removed in 2.5
    sed -i '/^#compat-names/d' "$processed_config"
    sed -i '/^no-name-remapping/d' "$processed_config"              # Removed in 2.5
    sed -i '/^#no-name-remapping/d' "$processed_config"
    sed -i '/^no-replay/d' "$processed_config"                      # Removed in 2.7
    sed -i '/^#no-replay/d' "$processed_config"
    sed -i '/^keysize/d' "$processed_config"                        # Removed in 2.6
    sed -i '/^#keysize/d' "$processed_config"
    
    # DEPRECATED options (comment out to avoid warnings):
    sed -i 's/^comp-lzo/#comp-lzo # Deprecated, pending removal/g' "$processed_config"
    sed -i 's/^comp-noadapt/#comp-noadapt # Deprecated, pending removal/g' "$processed_config"
    sed -i 's/^compress/#compress # Deprecated, pending removal/g' "$processed_config"
    sed -i 's/^ns-cert-type/#ns-cert-type # Deprecated, use --remote-cert-tls instead/g' "$processed_config"
    sed -i 's/^ncp-disable/#ncp-disable # Deprecated option/g' "$processed_config"
    
    # === LOG CONFIGURATION STANDARDIZATION (no protocol impact) ===
    # Force standardized log file names regardless of user's original naming
    
    # Standardize status log (regardless of original path/name)
    sed -i 's|^status .*|status /logs/openvpn-status.log|g' "$processed_config"
    
    # Standardize application logs (regardless of original path/name)
    sed -i 's|^log-append .*|log-append /logs/openvpn.log|g' "$processed_config"
    sed -i 's|^log .*|log /logs/openvpn.log|g' "$processed_config"
    
    # Add missing essential log directives (only if completely missing)
    if ! grep -q "^status " "$processed_config"; then
        log "Adding missing status log configuration"
        echo "status /logs/openvpn-status.log" >> "$processed_config"
    fi
    
    # Add log directive only if no logging is configured at all
    if ! grep -q "^log " "$processed_config" && ! grep -q "^log-append " "$processed_config"; then
        log "Adding missing log configuration"
        echo "log-append /logs/openvpn.log" >> "$processed_config"
    fi
    
    # === ALL FILE PATHS STANDARDIZATION (based on OpenVPN 2.6 manual) ===
    # Convert relative paths to absolute paths based on original config location
    local config_dir=$(dirname "$original_config")
    
    # Certificate and key files:
    sed -i "s|^ca \([^/].*\)|ca $config_dir/\1|g" "$processed_config"
    sed -i "s|^cert \([^/].*\)|cert $config_dir/\1|g" "$processed_config"  
    sed -i "s|^key \([^/].*\)|key $config_dir/\1|g" "$processed_config"
    sed -i "s|^askpass \([^/].*\)|askpass $config_dir/\1|g" "$processed_config"
    
    # TLS authentication files:
    sed -i "s|^tls-auth \([^/].*\)|tls-auth $config_dir/\1|g" "$processed_config"
    sed -i "s|^tls-crypt \([^/].*\)|tls-crypt $config_dir/\1|g" "$processed_config"
    sed -i "s|^tls-crypt-v2 \([^/].*\)|tls-crypt-v2 $config_dir/\1|g" "$processed_config"
    
    # Static key and secret files:
    sed -i "s|^secret \([^/].*\)|secret $config_dir/\1|g" "$processed_config"
    
    # Certificate revocation and DH files:
    sed -i "s|^crl-verify \([^/].*\)|crl-verify $config_dir/\1|g" "$processed_config"
    sed -i "s|^dh \([^/].*\)|dh $config_dir/\1|g" "$processed_config"
    sed -i "s|^pkcs12 \([^/].*\)|pkcs12 $config_dir/\1|g" "$processed_config"
    
    # Authentication files:
    sed -i "s|^auth-user-pass \([^/].*\)|auth-user-pass $config_dir/\1|g" "$processed_config"
    sed -i "s|^http-proxy-user-pass \([^/].*\)|http-proxy-user-pass $config_dir/\1|g" "$processed_config"
    
    # Configuration files:
    sed -i "s|^config \([^/].*\)|config $config_dir/\1|g" "$processed_config"
    
    # Script files (up/down/client-connect etc):
    sed -i "s|^up \([^/].*\)|up $config_dir/\1|g" "$processed_config"
    sed -i "s|^down \([^/].*\)|down $config_dir/\1|g" "$processed_config"
    sed -i "s|^client-connect \([^/].*\)|client-connect $config_dir/\1|g" "$processed_config"
    sed -i "s|^client-disconnect \([^/].*\)|client-disconnect $config_dir/\1|g" "$processed_config"
    sed -i "s|^learn-address \([^/].*\)|learn-address $config_dir/\1|g" "$processed_config"
    sed -i "s|^auth-user-pass-verify \([^/].*\)|auth-user-pass-verify $config_dir/\1|g" "$processed_config"
    
    # Process ID and other output files:
    sed -i "s|^writepid \([^/].*\)|writepid $config_dir/\1|g" "$processed_config"
    sed -i "s|^ifconfig-pool-persist \([^/].*\)|ifconfig-pool-persist $config_dir/\1|g" "$processed_config"
    
    # === ESSENTIAL CLIENT DIRECTIVES (only add if missing) ===
    # These are required for proper client operation
    if ! grep -q "^client" "$processed_config"; then
        log "Adding missing 'client' directive"
        echo "client" >> "$processed_config"
    fi
    
    # Add basic client essentials only if completely missing
    if ! grep -q "^dev " "$processed_config"; then
        echo "dev tun" >> "$processed_config"
    fi
    
    if ! grep -q "^nobind" "$processed_config"; then
        echo "nobind" >> "$processed_config"
    fi
    
    # Add persistence options for stability (only if missing)
    if ! grep -q "^persist-key" "$processed_config"; then
        echo "persist-key" >> "$processed_config"
    fi
    
    if ! grep -q "^persist-tun" "$processed_config"; then
        echo "persist-tun" >> "$processed_config"
    fi
    
    # Add route delay for connection stability (only if missing)
    if ! grep -q "^route-delay" "$processed_config"; then
        echo "route-delay 2" >> "$processed_config"
    fi
    
    # === WARNINGS FOR USER (comprehensive based on official docs) ===
    # Warn about deprecated options but don't force changes that could break compatibility
    
    if grep -q "comp-lzo" "$original_config"; then
        log "WARNING: comp-lzo is deprecated and pending removal. Consider removing it or using modern compression if server supports it"
    fi
    
    if grep -q "comp-noadapt" "$original_config"; then
        log "WARNING: comp-noadapt is deprecated and pending removal"
    fi
    
    if grep -q "compress" "$original_config"; then
        log "WARNING: compress directive is deprecated and pending removal. OpenVPN 2.7+ will not compress data"
    fi
    
    if grep -q "ns-cert-type" "$original_config"; then
        log "WARNING: ns-cert-type is deprecated. Use --remote-cert-tls instead"
    fi
    
    if grep -q "ncp-disable" "$original_config"; then
        log "WARNING: ncp-disable is deprecated. Modern servers should support negotiable crypto"
    fi
    
    # Check for removed options that would cause startup failure
    removed_options="no-iv client-cert-not-required ifconfig-pool-linear key-method tls-remote compat-names no-name-remapping no-replay keysize"
    for option in $removed_options; do
        if grep -q "^$option" "$original_config"; then
            log "ERROR: '$option' option has been removed in modern OpenVPN versions and will cause startup failure"
        fi
    done
    
    log "OpenVPN configuration preprocessed successfully"
    echo "$processed_config"
    return 0
}

# Preprocess OpenVPN configuration
PROCESSED_CONFIG=$(preprocess_ovpn_config "$OPENVPN_CONFIG_FILE")
if [ $? -ne 0 ]; then
    error "Failed to preprocess OpenVPN configuration"
    exit 1
fi

# Use processed config for OpenVPN
OPENVPN_CONFIG_FILE="$PROCESSED_CONFIG"

# Generate sing-box configuration
log "Generating sing-box configuration..."
CONFIG_FILE="/etc/sing-box/config.json"
cp /etc/sing-box/server.json "$CONFIG_FILE"

# Update configuration for host network mode
if [ "$USE_HOST_NETWORK" = "true" ]; then
    log "Configuring for host network mode (port 18080)..."
    sed -i 's/"listen_port": 1080/"listen_port": 18080/g' "$CONFIG_FILE"
fi

# Ensure consistent port configuration
log "Setting SOCKS5 port to: $SOCKS_PORT"
sed -i "s/\"listen_port\": [0-9]*/\"listen_port\": ${SOCKS_PORT:-18080}/g" "$CONFIG_FILE"

# Configure SOCKS5 authentication if provided
if [ -n "$SOCKS5_USERNAME" ] && [ -n "$SOCKS5_PASSWORD" ]; then
    log "Configuring SOCKS5 authentication for user: $SOCKS5_USERNAME"
    # Use jq to add authentication to the config
    jq --arg username "$SOCKS5_USERNAME" --arg password "$SOCKS5_PASSWORD" \
       '.inbounds[0].users = [{
           "username": $username,
           "password": $password
       }]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
else
    log "No SOCKS5 authentication configured, allowing anonymous access"
fi

# Function to get tun0 IP address
get_tun0_ip() {
    local retries=0
    local max_retries=30
    
    while [ $retries -lt $max_retries ]; do
        if ip addr show tun0 >/dev/null 2>&1; then
            local tun0_ip=$(ip route get 8.8.8.8 | grep tun0 | awk '{print $7}' | head -1)
            if [ -n "$tun0_ip" ]; then
                echo "$tun0_ip"
                return 0
            fi
        fi
        retries=$((retries + 1))
        sleep 2
    done
    return 1
}

# Function to update sing-box config (simplified since we're using auto_detect_interface)
update_singbox_config() {
    local tun0_ip="$1"
    if [ -n "$tun0_ip" ]; then
        log "VPN tun0 IP detected: $tun0_ip"
    else
        warn "Could not determine tun0 IP, using auto-detection"
    fi
}

# Function to start sing-box
start_singbox() {
    log "Starting sing-box SOCKS5 proxy on port 18080..."
    
    # Validate configuration
    if ! sing-box check -c "$CONFIG_FILE"; then
        error "sing-box configuration validation failed"
        return 1
    fi
    
    # Start sing-box in background
    sing-box run -c "$CONFIG_FILE" &
    SINGBOX_PID=$!
    
    # Wait a moment and check if sing-box is running
    sleep 3
    if ! kill -0 $SINGBOX_PID 2>/dev/null; then
        error "sing-box failed to start"
        return 1
    fi
    
    log "sing-box started successfully with PID: $SINGBOX_PID"
    return 0
}

# Function to setup routing and iptables rules
setup_routing() {
    log "Setting up routing and iptables rules..."
    
    # Enable IP forwarding (may fail in some container environments)
    if echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null; then
        log "IP forwarding enabled"
    else
        warn "Could not enable IP forwarding (container limitation)"
    fi
    
    # Fix default route to use VPN (but keep VPN server route)
    local vpn_server=$(grep "remote " /config/config.ovpn | awk '{print $2}')
    if [ -n "$vpn_server" ]; then
        # Add specific route for VPN server through eth0
        ip route add $vpn_server via $(ip route | grep "default via" | head -1 | awk '{print $3}') dev eth0 2>/dev/null || true
    fi
    
    # Delete default route through eth0 and add through tun0
    ip route del default via $(ip route | grep "default via" | grep eth0 | awk '{print $3}') dev eth0 2>/dev/null || true
    ip route add default via 10.10.1.177 dev tun0 2>/dev/null || true
    
    # Setup iptables for tun0 interface
    iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
    
    log "Routing and iptables rules configured"
}

# Function to wait for OpenVPN connection
wait_for_vpn() {
    local retries=0
    local max_retries=60
    
    log "Waiting for OpenVPN connection to establish..."
    
    while [ $retries -lt $max_retries ]; do
        if ip link show tun0 >/dev/null 2>&1; then
            local tun0_ip=$(get_tun0_ip)
            if [ -n "$tun0_ip" ]; then
                log "OpenVPN connection established. tun0 IP: $tun0_ip"
                update_singbox_config "$tun0_ip"
                return 0
            fi
        fi
        retries=$((retries + 1))
        sleep 5
        info "Waiting for VPN connection... ($retries/$max_retries)"
    done
    
    error "Timeout waiting for OpenVPN connection"
    return 1
}

# Function to test connectivity
test_connectivity() {
    log "Testing connectivity..."
    
    # Test basic connectivity through tun0
    if ping -c 3 -I tun0 8.8.8.8 >/dev/null 2>&1; then
        log "✓ Basic connectivity through VPN successful"
    else
        warn "⚠ Basic connectivity test failed"
    fi
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        log "✓ DNS resolution working"
    else
        warn "⚠ DNS resolution test failed"
    fi
}

# Cleanup function
cleanup() {
    log "Shutting down services..."
    
    # Stop sing-box
    if [ -n "$SINGBOX_PID" ]; then
        kill $SINGBOX_PID 2>/dev/null || true
        wait $SINGBOX_PID 2>/dev/null || true
        log "sing-box stopped"
    fi
    
    # Stop OpenVPN
    if [ -n "$OPENVPN_PID" ]; then
        kill $OPENVPN_PID 2>/dev/null || true
        wait $OPENVPN_PID 2>/dev/null || true
        log "OpenVPN stopped"
    fi
    
    log "Cleanup completed"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main execution
log "=== OpenVPN + sing-box SOCKS5 Proxy Starting ==="
log "Config file: $OPENVPN_CONFIG_FILE"
log "SOCKS5 port: 18080"
log "UDP support: $ENABLE_UDP"

if [ -n "$SOCKS5_USERNAME" ]; then
    log "SOCKS5 authentication: enabled (user: $SOCKS5_USERNAME)"
else
    log "SOCKS5 authentication: disabled"
fi

# Start OpenVPN in background
log "Starting OpenVPN..."
# No need to change directory as we use absolute paths
openvpn \
    --config "$OPENVPN_CONFIG_FILE" \
    --script-security 2 \
    --up /usr/local/bin/openvpn_up.sh \
    --down /usr/local/bin/openvpn_up.sh \
    --log-append /logs/openvpn.log \
    --verb 3 \
    $OPENVPN_AUTH_OPTION &
OPENVPN_PID=$!

# Wait a moment to check if OpenVPN started
sleep 3
if ! kill -0 $OPENVPN_PID 2>/dev/null; then
    error "Failed to start OpenVPN - check /logs/openvpn.log for details"
    if [ -f /logs/openvpn.log ]; then
        tail -20 /logs/openvpn.log >&2
    fi
    exit 1
fi

log "OpenVPN started with PID: $OPENVPN_PID"

# Wait for VPN connection
if ! wait_for_vpn; then
    error "VPN connection failed"
    exit 1
fi

# Setup routing and iptables
if [ "$ENABLE_UDP" = "true" ]; then
    setup_routing
fi

# Start sing-box
if ! start_singbox; then
    error "Failed to start sing-box"
    exit 1
fi

# Test connectivity
test_connectivity

# Display connection info
log "=== Connection Information ==="
log "OpenVPN Status: Connected"
log "SOCKS5 Proxy: sing-box listening on 0.0.0.0:$SOCKS_PORT"
log "VPN Interface: tun0 ($(get_tun0_ip))"
log "Authentication: $([ -n "$SOCKS5_USERNAME" ] && echo "enabled" || echo "disabled")"
log "UDP Support: $ENABLE_UDP"
log "=== Ready for connections ==="

# Monitor processes and logs
log "Monitoring services... (Ctrl+C to stop)"

# Function to monitor processes
monitor_processes() {
    while true; do
        # Check OpenVPN
        if ! kill -0 $OPENVPN_PID 2>/dev/null; then
            error "OpenVPN process died, restarting..."
            cleanup
        fi
        
        # Check sing-box
        if ! kill -0 $SINGBOX_PID 2>/dev/null; then
            error "sing-box process died, restarting..."
            start_singbox || cleanup
        fi
        
        # Check tun0 interface
        if ! ip link show tun0 >/dev/null 2>&1; then
            error "tun0 interface is down"
            cleanup
        fi
        
        sleep 30
    done
}

# Start monitoring in background and wait
monitor_processes &
MONITOR_PID=$!

# Wait for signals
wait $MONITOR_PID