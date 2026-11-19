#!/bin/bash
set -eu
umask 077
node /app/initialize.js

export FILE_SERVER_PORT HTTP_PORT ZT_ADDR ZT_TOKEN
zt_port=$(cat /app/config/zerotier-one.port)
FILE_SERVER_PORT=$(cat /app/config/file_server.port)
HTTP_PORT=$(cat /app/config/ztncui.port)
ZT_ADDR="127.0.0.1:$zt_port"
ZT_TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret)

pids=()
stop_children() {
    if (( ${#pids[@]} )); then
        kill "${pids[@]}" 2>/dev/null || true
        wait "${pids[@]}" 2>/dev/null || true
    fi
}
trap stop_children EXIT
trap 'exit 0' TERM INT
/usr/sbin/zerotier-one "-p$zt_port" /var/lib/zerotier-one &
pids+=("$!")
node /app/http_server.js &
pids+=("$!")
cd /opt/ztncui/src
node ./bin/www &
pids+=("$!")
# Any unexpected child exit must stop the whole container for Docker to retry.
wait -n || true
exit 1
