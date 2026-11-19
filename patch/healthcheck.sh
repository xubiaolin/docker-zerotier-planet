#!/bin/sh
set -eu
zt_port=$(cat /app/config/zerotier-one.port)
web_port=$(cat /app/config/ztncui.port)
file_port=$(cat /app/config/file_server.port)
token=$(cat /var/lib/zerotier-one/authtoken.secret)
key=$(cat /app/config/file_server.key)
node_id=$(cat /app/config/.planet-initialized)
case "$node_id" in
    *[!0-9a-f]*|'') exit 1 ;;
esac
[ "${#node_id}" -eq 10 ]
moon="000000$node_id.moon"
curl -fsS --max-time 2 -H "X-ZT1-Auth: $token" "http://127.0.0.1:$zt_port/controller/network" >/dev/null
curl -fsS --max-time 2 "http://127.0.0.1:$web_port/" >/dev/null
for file in planet "$moon"; do
    [ -s "/app/dist/$file" ]
    printf '%s' "$key" | curl -fsSI --max-time 2 -G --data-urlencode key@- "http://127.0.0.1:$file_port/$file" >/dev/null
done
