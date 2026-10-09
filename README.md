# xray-vless-mikrotik-arm64

VLESS-клиент (Xray-core) в контейнере для **MikroTik RouterOS 7.x на ARM64** (hAP ax³, RB5009 и др.).
Трафик заворачивается в TUN через hev-socks5-tunnel и уходит на VLESS-сервер.

Docker Hub: [`aznka/xray-vless-mikrotik-arm64`](https://hub.docker.com/r/aznka/xray-vless-mikrotik-arm64)

## Возможности

- Транспорты: TCP+Vision, XHTTP (SplitHTTP), gRPC, WebSocket, H2, HTTPUpgrade
- Безопасность: Reality и TLS
- Автоматический разбор share-ссылки `vless://…` из переменной `VLESS_URL`
- Xray-core, hev-socks5-tunnel, Alpine Linux

| Транспорт | `type=` | Security | UDP | Примечание |
|---|---|---|---|---|
| TCP + Vision | `tcp` | reality | нет | `flow=xtls-rprx-vision` |
| XHTTP | `xhttp` | reality | да | рекомендуется |
| gRPC | `grpc` | reality / tls | да | `serviceName`, `authority`, `mode=multi` |
| WebSocket | `ws` | tls | да | совместим с CDN |
| H2 | `h2` | reality / tls | да | |
| HTTPUpgrade | `httpupgrade` | tls | да | совместим с CDN |

## Быстрый старт на MikroTik

```
/interface/veth/add name=veth-vless address=172.18.20.2/24 gateway=172.18.20.1
/interface/bridge/add name=br-containers
/ip/address/add address=172.18.20.1/24 interface=br-containers
/interface/bridge/port/add bridge=br-containers interface=veth-vless

/container/config/set registry-url=https://registry-1.docker.io tmpdir=usb1/tmp
/container/envs/add list=vless key=VLESS_URL value="vless://UUID@server:443?type=xhttp&security=reality&pbk=KEY&fp=chrome&sni=example.com&sid=SHORTID&path=/&mode=auto"

/container/add remote-image=aznka/xray-vless-mikrotik-arm64:latest interface=veth-vless root-dir=usb1/vless envlist=vless logging=yes start-on-boot=yes
/container/start [find where interface=veth-vless]

/routing/table/add name=vless fib
/ip/route/add dst-address=0.0.0.0/0 gateway=172.18.20.2 routing-table=vless
```

Дальше направьте нужный трафик в таблицу `vless` через `/routing/rule` или mangle `mark-routing`.
Синтаксис `/container` немного различается между версиями RouterOS 7.x — сверяйтесь с документацией своей версии.

Логи: `/log print where topics~"container"`

> **Важно:** значение `VLESS_URL` должно содержать ссылку `vless://…`. Начиная с 3.3.2 пробелы,
> кавычки и невидимые символы вокруг ссылки отбрасываются автоматически.

### Примеры ссылок

```
# XHTTP + Reality
vless://UUID@server:443?type=xhttp&security=reality&pbk=KEY&fp=chrome&sni=example.com&sid=SHORTID&path=/&mode=auto

# gRPC + Reality
vless://UUID@server:443?type=grpc&serviceName=&security=reality&pbk=KEY&fp=chrome&sni=example.com&sid=SHORTID

# TCP + Reality + Vision
vless://UUID@server:443?type=tcp&security=reality&flow=xtls-rprx-vision&pbk=KEY&fp=chrome&sni=example.com&sid=SHORTID
```

## Переменные окружения

| Переменная | По умолчанию | Описание |
|---|---|---|
| `VLESS_URL` | — | Share-ссылка `vless://…`; если задана, перекрывает ручные параметры |
| `TUN` | `tun0` | Имя TUN-интерфейса (уникальное для каждого контейнера) |
| `MTU` | `9000` | MTU TUN-интерфейса |
| `IPV4` / `IPV6` | `198.18.0.1` / — | Адреса TUN |
| `MARK` | `438` | fwmark для трафика socks5 |
| `SOCKS_PORT` | `1080` | Внутренний порт SOCKS5 |
| `SOCKS5_UDP_MODE` | `udp` | Режим UDP в hev-socks5-tunnel |
| `GATEWAY` | автоопределение | Шлюз контейнера |
| `OTHER_ROUTE` | — | Доп. команды `ip route` после поднятия TUN |
| `LOG_LEVEL` | `warn` | `debug` / `info` / `warn` / `error` (`debug` печатает сгенерированный конфиг) |

Ручная настройка без `VLESS_URL`: `REMOTE_ADDRESS`, `REMOTE_PORT`, `ID`, `TRANSPORT`, `SECURITY`, `FLOW`,
`SERVER_NAME`, `FINGER_PRINT`, `PUBLIC_KEY`, `SHORT_ID`, `SPIDERX`, `XHTTP_PATH`, `XHTTP_MODE`,
`GRPC_SERVICE_NAME`, `GRPC_MULTI_MODE`, `GRPC_AUTHORITY`.

## Сборка

```
docker buildx build --platform linux/arm64 --provenance=false --sbom=false \
  -t aznka/xray-vless-mikrotik-arm64:dev --push .
```

## Changelog

См. [CHANGELOG.md](CHANGELOG.md).

## Лицензия

MIT. Используются [Xray-core](https://github.com/XTLS/Xray-core) и
[hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel).
