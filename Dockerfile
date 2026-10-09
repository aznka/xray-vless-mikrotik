FROM aznka/xray-vless-mikrotik-arm64:3.3.1@sha256:ee57a06ee548a8b2418b4de958a2d61dcd981947baf02ce304b264a51793e3a3
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
