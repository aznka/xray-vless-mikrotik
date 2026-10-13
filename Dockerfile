# syntax=docker/dockerfile:1
ARG BASE=aznka/xray-vless-mikrotik-arm64:v3.3.1@sha256:ee57a06ee548a8b2418b4de958a2d61dcd981947baf02ce304b264a51793e3a3

FROM --platform=$BUILDPLATFORM alpine:3.21 AS fetch
ARG XRAY_VERSION=26.3.27
ARG HEV_VERSION=2.18.0
RUN apk add --no-cache wget unzip
WORKDIR /dl
RUN set -e; Z=Xray-linux-arm64-v8a.zip; \
    wget -q "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/$Z" \
         "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/$Z.dgst"; \
    H=$(grep 'SHA2-256=' "$Z.dgst" | awk '{print $2}'); \
    echo "$H  $Z" | sha256sum -c -; \
    unzip -q "$Z" -d xray; \
    wget -q -O hev "https://github.com/heiher/hev-socks5-tunnel/releases/download/${HEV_VERSION}/hev-socks5-tunnel-linux-arm64"; \
    chmod +x xray/xray hev

FROM ${BASE}
COPY --from=fetch /dl/xray/xray /tmp/new/xray
COPY --from=fetch /dl/xray/geoip.dat /dl/xray/geosite.dat /tmp/new/
COPY --from=fetch /dl/hev /tmp/new/hev
RUN set -e; X=$(command -v xray); H=$(command -v hev-socks5-tunnel); \
    install -m755 /tmp/new/xray "$X"; install -m755 /tmp/new/hev "$H"; \
    for f in geoip.dat geosite.dat; do for d in "$(dirname "$X")" /usr/local/share/xray /usr/share/xray; do \
      [ -f "$d/$f" ] && install -m644 "/tmp/new/$f" "$d/$f"; done; done; \
    rm -rf /tmp/new; xray version | head -1
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 tests/xray-config-test.sh /usr/local/bin/xray-config-test
ENTRYPOINT ["/entrypoint.sh"]
