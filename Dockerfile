FROM aznka/xray-vless-mikrotik-arm64:latest
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
