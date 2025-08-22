FROM alpine:3.19

LABEL maintainer="OpenVPN SOCKS5 Proxy"
LABEL description="OpenVPN client with sing-box SOCKS5 proxy"

# Install required packages
RUN apk add --no-cache \
    openvpn \
    iptables \
    ip6tables \
    curl \
    bash \
    jq \
    tini \
    ca-certificates \
    tzdata \
    iproute2 \
    iputils \
    bind-tools \
    net-tools \
    procps \
    && rm -rf /var/cache/apk/*

# Download and install sing-box v1.10.7
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then ARCH="arm64"; \
    elif [ "$ARCH" = "armv7l" ]; then ARCH="armv7"; \
    fi && \
    curl -L "https://github.com/SagerNet/sing-box/releases/download/v1.10.7/sing-box-1.10.7-linux-${ARCH}.tar.gz" -o /tmp/sing-box.tar.gz && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv /tmp/sing-box-*/sing-box /usr/local/bin/ && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/sing-box*

# Create necessary directories
RUN mkdir -p /config /logs /etc/sing-box /usr/local/bin

# Copy configuration files
COPY conf/server.json /etc/sing-box/
COPY scripts/openvpn_up.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/

# Set permissions
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/openvpn_up.sh

# Environment variables with defaults
ENV OPENVPN_CONFIG_FILE=/config/config.ovpn
ENV SOCKS_PORT=18080
ENV ENABLE_UDP=true
ENV USE_HOST_NETWORK=false

# Expose SOCKS5 port
EXPOSE 18080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD netstat -tlnp | grep :18080 || exit 1

# Use tini for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]