#!/bin/sh
# ===========================================
# Xray VLESS Client Container for MikroTik
# Supports: TCP+Reality+Vision, XHTTP+Reality, gRPC+Reality, WS, H2
# Version: 3.3.2
# ===========================================

# Tunnel settings
TUN="${TUN:-tun0}"
MTU="${MTU:-9000}"
IPV4="${IPV4:-198.18.0.1}"
IPV6="${IPV6:-}"
MARK="${MARK:-438}"
SOCKS5_UDP_MODE="${SOCKS5_UDP_MODE:-udp}"
OTHER_ROUTE="${OTHER_ROUTE:-}"
LOG_LEVEL="${LOG_LEVEL:-warn}"
ETH_IFACE=$(ip -o link show | awk -F': ' '/link\/ether/ {print $2}' | cut -d'@' -f1 | head -n1)
GATEWAY="${GATEWAY:-$(ip route | awk -v iface="$ETH_IFACE" '$0 ~ "default" && $0 ~ iface {print $3}')}"

# Xray settings
SOCKS_PORT="${SOCKS_PORT:-1080}"
REMOTE_ADDRESS="${REMOTE_ADDRESS:-}"
REMOTE_PORT="${REMOTE_PORT:-443}"
ID="${ID:-}"
ENCRYPTION="${ENCRYPTION:-none}"
FINGER_PRINT="${FINGER_PRINT:-chrome}"
SERVER_NAME="${SERVER_NAME:-yahoo.com}"
PUBLIC_KEY="${PUBLIC_KEY:-}"
SPIDERX="${SPIDERX:-}"
SHORT_ID="${SHORT_ID:-}"

# Transport settings
TRANSPORT="${TRANSPORT:-xhttp}"
SECURITY="${SECURITY:-reality}"
FLOW="${FLOW:-}"

# XHTTP specific
XHTTP_PATH="${XHTTP_PATH:-/}"
XHTTP_MODE="${XHTTP_MODE:-auto}"

# gRPC specific - empty by default, не подставляем дефолт
GRPC_SERVICE_NAME="${GRPC_SERVICE_NAME:-}"
GRPC_MULTI_MODE="${GRPC_MULTI_MODE:-false}"

# Parse VLESS URL if provided
if [ -n "$VLESS_URL" ]; then
    echo "[INFO] Parsing VLESS URL..."
    # strip \r \n \t and any garbage before vless:// (spaces, quotes, BOM, zero-width)
    VLESS_URL=$(printf '%s' "$VLESS_URL" | tr -d '\r\n\t')
    case "$VLESS_URL" in
        *[Vv][Ll][Ee][Ss][Ss]://*) url="${VLESS_URL#*://}" ;;
        *) echo "[ERROR] VLESS_URL does not contain vless://"; exit 1 ;;
    esac
    url="${url%\"}"; url="${url%\'}"
    ID="${url%%@*}"
    case "$ID" in
        ""|*://*|*[[:space:]]*|*\"*)
            echo "[ERROR] Cannot extract UUID from VLESS_URL: '$ID'"; exit 1 ;;
    esac
    rest="${url#*@}"
    addr_port="${rest%%[\?#]*}"
    REMOTE_ADDRESS="${addr_port%:*}"
    REMOTE_PORT="${addr_port##*:}"

    case "$rest" in
        *\?*)
            params="${rest#*\?}"
            params="${params%%#*}"
            OLD_IFS="$IFS"
            IFS='&'
            for param in $params; do
                key="${param%%=*}"
                value="${param#*=}"
                value=$(printf '%b' "${value//%/\\x}")
                case "$key" in
                    type) TRANSPORT="$value" ;;
                    security) SECURITY="$value" ;;
                    flow) FLOW="$value" ;;
                    sni|serverName) SERVER_NAME="$value" ;;
                    fp|fingerprint) FINGER_PRINT="$value" ;;
                    pbk|publicKey) PUBLIC_KEY="$value" ;;
                    sid|shortId) SHORT_ID="$value" ;;
                    spx) SPIDERX="$value" ;;
                    path) XHTTP_PATH="$value" ;;
                    mode) XHTTP_MODE="$value"
                          [ "$value" = "multi" ] && GRPC_MULTI_MODE=true ;;
                    # gRPC specific parameters
                    serviceName) GRPC_SERVICE_NAME="$value" ;;
                    authority) GRPC_AUTHORITY="$value" ;;
                esac
            done
            IFS="$OLD_IFS"
            ;;
    esac
    echo "[INFO] Parsed: ${REMOTE_ADDRESS}:${REMOTE_PORT}"
    echo "[INFO] Transport: ${TRANSPORT}, Security: ${SECURITY}"
    [ -n "$FLOW" ] && echo "[INFO] Flow: ${FLOW}"
    [ -n "$GRPC_SERVICE_NAME" ] && echo "[INFO] gRPC serviceName: ${GRPC_SERVICE_NAME}"
    [ "$TRANSPORT" = "grpc" ] && [ -z "$GRPC_SERVICE_NAME" ] && echo "[INFO] gRPC serviceName: (empty)"
fi

config_file() {
  cat > /hs5t.yml << HEVEOF
misc:
  log-level: '${LOG_LEVEL}'
tunnel:
  name: '${TUN}'
  mtu: ${MTU}
  ipv4: '${IPV4}'
  ipv6: '${IPV6}'
  post-up-script: '/route.sh'
socks5:
  address: '127.0.0.1'
  port: ${SOCKS_PORT}
  udp: '${SOCKS5_UDP_MODE}'
  mark: ${MARK}
HEVEOF
}

config_route() {
  cat > /route.sh << ROUTESCRIPT
#!/bin/sh
ip rule add from all uidrange 1000-1000 lookup 110 pref 28000 2>/dev/null || true
ip route flush table 110 2>/dev/null || true
ip route add default via $GATEWAY dev $ETH_IFACE metric 50 table 110
ip route del default 2>/dev/null || true
ip route add default via ${IPV4} dev ${TUN} metric 1
ip route add default via $GATEWAY dev $ETH_IFACE metric 10
ip route add 10.0.0.0/8 via $GATEWAY dev $ETH_IFACE 2>/dev/null || true
ip route add 172.16.0.0/12 via $GATEWAY dev $ETH_IFACE 2>/dev/null || true
ip route add 192.168.0.0/16 via $GATEWAY dev $ETH_IFACE 2>/dev/null || true
${OTHER_ROUTE}
ROUTESCRIPT
  chmod +x /route.sh
}

config_file_xray() {
  if [ -n "$FLOW" ]; then
    USER_BLOCK="{\"id\": \"${ID}\", \"encryption\": \"${ENCRYPTION}\", \"flow\": \"${FLOW}\"}"
  else
    USER_BLOCK="{\"id\": \"${ID}\", \"encryption\": \"${ENCRYPTION}\"}"
  fi

  # XTLS-Vision incompatible with TLS sniffing
  if [ -n "$FLOW" ] && echo "$FLOW" | grep -q "vision"; then
    echo "[INFO] Vision flow detected - disabling TLS sniffing"
    SNIFFING='"sniffing":{"enabled":true,"destOverride":["http","quic"],"routeOnly":true}'
  else
    SNIFFING='"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}'
  fi

  # Security settings
  case "$SECURITY" in
    reality)
      SEC_SETTINGS="\"security\":\"reality\",\"realitySettings\":{\"fingerprint\":\"${FINGER_PRINT}\",\"serverName\":\"${SERVER_NAME}\",\"publicKey\":\"${PUBLIC_KEY}\",\"spiderX\":\"${SPIDERX}\",\"shortId\":\"${SHORT_ID}\"}"
      ;;
    tls)
      # For gRPC, h2 should be first in ALPN for proper HTTP/2 handshake
      if [ "$TRANSPORT" = "grpc" ]; then
        SEC_SETTINGS="\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"${SERVER_NAME}\",\"fingerprint\":\"${FINGER_PRINT}\",\"alpn\":[\"h2\",\"http/1.1\"]}"
      else
        SEC_SETTINGS="\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"${SERVER_NAME}\",\"fingerprint\":\"${FINGER_PRINT}\"}"
      fi
      ;;
    *)
      SEC_SETTINGS="\"security\":\"none\""
      ;;
  esac

  # Transport settings
  case "$TRANSPORT" in
    tcp)
      STREAM="\"network\":\"tcp\",${SEC_SETTINGS}"
      ;;
    grpc)
      # gRPC - serviceName может быть пустым, это нормально
      GRPC_OPTS="\"serviceName\":\"${GRPC_SERVICE_NAME}\""
      if [ "$GRPC_MULTI_MODE" = "true" ]; then
        GRPC_OPTS="${GRPC_OPTS},\"multiMode\":true"
      fi
      # Add authority if specified (for some CDN setups)
      if [ -n "$GRPC_AUTHORITY" ]; then
        GRPC_OPTS="${GRPC_OPTS},\"authority\":\"${GRPC_AUTHORITY}\""
      fi
      STREAM="\"network\":\"grpc\",\"grpcSettings\":{${GRPC_OPTS}},${SEC_SETTINGS}"
      ;;
    xhttp|splithttp)
      STREAM="\"network\":\"xhttp\",\"xhttpSettings\":{\"path\":\"${XHTTP_PATH}\",\"mode\":\"${XHTTP_MODE}\"},${SEC_SETTINGS}"
      ;;
    ws|websocket)
      WS_PATH="${XHTTP_PATH:-/}"
      STREAM="\"network\":\"ws\",\"wsSettings\":{\"path\":\"${WS_PATH}\"},${SEC_SETTINGS}"
      ;;
    h2|http)
      H2_PATH="${XHTTP_PATH:-/}"
      STREAM="\"network\":\"h2\",\"httpSettings\":{\"path\":\"${H2_PATH}\"},${SEC_SETTINGS}"
      ;;
    httpupgrade)
      HU_PATH="${XHTTP_PATH:-/}"
      STREAM="\"network\":\"httpupgrade\",\"httpupgradeSettings\":{\"path\":\"${HU_PATH}\"},${SEC_SETTINGS}"
      ;;
    *)
      echo "[WARN] Unknown transport '${TRANSPORT}', falling back to xhttp"
      STREAM="\"network\":\"xhttp\",\"xhttpSettings\":{\"path\":\"${XHTTP_PATH}\",\"mode\":\"${XHTTP_MODE}\"},${SEC_SETTINGS}"
      ;;
  esac

  cat > /etc/xray/config.json << XRAYEOF
{"log":{"loglevel":"${LOG_LEVEL}"},"inbounds":[{"listen":"0.0.0.0","port":${SOCKS_PORT},"protocol":"socks","settings":{"udp":true},${SNIFFING}}],"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"${REMOTE_ADDRESS}","port":${REMOTE_PORT},"users":[${USER_BLOCK}]}]},"streamSettings":{${STREAM}},"tag":"proxy"}]}
XRAYEOF
}

run() {
  case "$TRANSPORT" in
    tcp) TRANSPORT_DISPLAY="TCP"; [ -n "$FLOW" ] && TRANSPORT_DISPLAY="${TRANSPORT_DISPLAY}+Vision" ;;
    xhttp|splithttp) TRANSPORT_DISPLAY="XHTTP(${XHTTP_MODE})" ;;
    grpc) 
      if [ -n "$GRPC_SERVICE_NAME" ]; then
        TRANSPORT_DISPLAY="gRPC(${GRPC_SERVICE_NAME})"
      else
        TRANSPORT_DISPLAY="gRPC(default)"
      fi
      ;;
    ws|websocket) TRANSPORT_DISPLAY="WebSocket" ;;
    h2|http) TRANSPORT_DISPLAY="H2" ;;
    httpupgrade) TRANSPORT_DISPLAY="HTTPUpgrade" ;;
    *) TRANSPORT_DISPLAY="${TRANSPORT}" ;;
  esac
  [ "$SECURITY" = "reality" ] && TRANSPORT_DISPLAY="${TRANSPORT_DISPLAY}+Reality"
  [ "$SECURITY" = "tls" ] && TRANSPORT_DISPLAY="${TRANSPORT_DISPLAY}+TLS"

  echo "========================================="
  echo "Xray VLESS Client v3.3.2"
  echo "-----------------------------------------"
  echo "Transport: ${TRANSPORT_DISPLAY}"
  echo "Server:    ${REMOTE_ADDRESS}:${REMOTE_PORT}"
  echo "UUID:      $(printf '%s' "$ID" | cut -c1-8)..."
  echo "SNI:       ${SERVER_NAME}"
  [ -n "$FLOW" ] && echo "Flow:      ${FLOW}"
  [ "$TRANSPORT" = "grpc" ] && echo "Service:   ${GRPC_SERVICE_NAME:-(empty)}"
  echo "TUN:       ${TUN} (${IPV4})"
  echo "Gateway:   ${GATEWAY}"
  echo "========================================="

  config_file
  config_file_xray
  config_route

  # Debug: show generated config
  if [ "$LOG_LEVEL" = "debug" ]; then
    echo "[DEBUG] Generated Xray config:"
    cat /etc/xray/config.json | head -c 2000
    echo ""
  fi

  echo "[INFO] Starting hev-socks5-tunnel..."
  hev-socks5-tunnel /hs5t.yml &
  sleep 1

  echo "[INFO] Starting Xray..."
  su - xray -c "xray -config /etc/xray/config.json"
}

run || exit 1
