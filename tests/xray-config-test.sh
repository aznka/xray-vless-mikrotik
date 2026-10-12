#!/bin/sh
# Генерирует конфиг Xray для каждого транспорта через entrypoint.sh
# и проверяет его командой `xray run -test`. Запускать внутри образа.
K=p9-6tdL4r6Tj8gj-2GIMbQalZe_McqjYN8Dm7Krrk7c
U=283dafa7-1111-2222-3333-444455556666
R="security=reality&pbk=$K&fp=chrome&sni=www.microsoft.com&sid=6ba85179e30d4fc2"
sed '$d' /entrypoint.sh > /tmp/ep.sh
fail=0
while IFS='|' read -r name url; do
  [ -z "$name" ] && continue
  if ( VLESS_URL="$url"; . /tmp/ep.sh >/dev/null 2>&1; config_file_xray >/dev/null 2>&1
       xray run -test -config /etc/xray/config.json >/tmp/out 2>&1 ); then
    echo "OK    $name"
  else
    echo "FAIL  $name"; grep -v '^\s*$' /tmp/out | tail -3 | sed 's/^/      /'; fail=1
  fi
done <<LIST
tcp+vision+reality|vless://$U@srv:443?type=tcp&flow=xtls-rprx-vision&$R
xhttp+reality|vless://$U@srv:443?type=xhttp&path=/&mode=auto&$R
grpc+reality|vless://$U@srv:443?type=grpc&serviceName=&$R
grpc-multi+reality| vless://$U@srv:443?type=grpc&serviceName=svc&mode=multi&$R#a@b
grpc+tls|vless://$U@srv:443?type=grpc&serviceName=svc&security=tls&sni=example.com&fp=chrome
ws+tls|vless://$U@srv:443?type=ws&path=/ws&security=tls&sni=example.com&fp=chrome
httpupgrade+tls|vless://$U@srv:443?type=httpupgrade&path=/hu&security=tls&sni=example.com&fp=chrome
h2+reality|vless://$U@srv:443?type=h2&path=/&$R
h2+tls|vless://$U@srv:443?type=h2&path=/&security=tls&sni=example.com&fp=chrome
LIST
exit $fail
