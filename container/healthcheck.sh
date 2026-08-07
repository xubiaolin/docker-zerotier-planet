#!/bin/sh

set -eu

CONFIG_PATH=${CONFIG_PATH:-/app/config}
ZT_PORT=${ZT_PORT:-$(cat "$CONFIG_PATH/zerotier-one.port")}
API_PORT=${API_PORT:-$(cat "$CONFIG_PATH/ztncui.port")}
FILE_SERVER_PORT=${FILE_SERVER_PORT:-$(cat "$CONFIG_PATH/file_server.port")}
ZT_TOKEN=$(cat "${ZEROTIER_PATH:-/var/lib/zerotier-one}/authtoken.secret")

zerotier-cli -T"$ZT_TOKEN" -p"$ZT_PORT" info >/dev/null 2>&1
curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:$API_PORT/" >/dev/null
curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:$FILE_SERVER_PORT/healthz" >/dev/null
