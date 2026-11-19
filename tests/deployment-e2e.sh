#!/usr/bin/env bash
# Run against a locally built candidate and the published pre-refactor image.
# Creates a private deployment, an authorized client and a failed update.
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd -P)
candidate=$(docker image inspect --format '{{.Id}}' "${1:?supply the locally built image}")
[[ $(docker image inspect --format '{{index .Config.Labels "org.zerotier-planet.secure-admin"}}' "$candidate") == 1 ]]
legacy=${2:-xubiaolin/zerotier-planet@sha256:55611f7107fb48c33ecffa132a694b6c3f23cdb61f2317def309447d24d34fdb}
docker image inspect "$legacy" >/dev/null 2>&1 || docker pull "$legacy" >/dev/null
work=$(mktemp -d)
cd "$work"
export CONTAINER_NAME=planet-e2e-$$ DOCKER_IMAGE=$legacy
client=$CONTAINER_NAME-client
broken=planet-failed-upgrade-$$:test
port_holder=
cleanup() {
    if [[ -n $port_holder ]]; then kill "$port_holder" 2>/dev/null || true; fi
    docker rm -fv "$CONTAINER_NAME" "$client" >/dev/null 2>&1 || true
    docker image rm "$broken" >/dev/null 2>&1 || true
    docker run --rm --network none -v "$work:/cleanup" --entrypoint sh "$legacy" \
        -c 'find /cleanup -mindepth 1 -maxdepth 1 -exec rm -rf {} +' >/dev/null
    rmdir "$work"
}
trap cleanup EXIT
# Keep one management port occupied until the retry chooses a different port.
python3 - "$work/ports" <<'PY' &
import signal
import socket
import sys
sockets = [socket.socket() for i in range(5)]
for s in sockets:
    s.bind(('', 0))
sockets[3].listen()
with open(sys.argv[1], 'w') as out:
    print(*(s.getsockname()[1] for s in sockets), file=out)
for i in (0, 1, 2, 4):
    sockets[i].close()
signal.pause()
PY
port_holder=$!
for ((i=0; i<50; i++)); do [[ ! -s ports ]] || break; sleep .1; done
read -r port api files occupied mapped_api <ports
address=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')

fetch_form() {
    curl --fail --silent --show-error --max-time 5 --noproxy '*' "$@" |
        python3 -c '
import re
import sys
match = re.search(r"name=\"_csrf\"\s+value=\"([A-Za-z0-9_-]+)\"", sys.stdin.read())
if match is None:
    sys.exit("Form is missing its CSRF token")
print(match[1])'
}

login() {
    local port=$1 password=$2 url cookies token
    shift 2
    url="http://127.0.0.1:$port/login"
    cookies="$work/login.cookies"
    token=$(fetch_form -c "$cookies" "$url") || return 1
    printf 'username=admin&password=%s&_csrf=%s' "$password" "$token" | \
        curl --silent --show-error --max-time 5 --noproxy '*' -b "$cookies" --data-binary @- "$@" "$url"
}
# Exercise first installation through the menu, with the same ports reused
# later by the separate legacy fixture after this container has been removed.
mkdir first-install
(
    cd first-install
    if printf '1\n%s\n%s\n%s\nn\ninvalid IP\n\n' "$port" "$api" "$files" |
        DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null 2>&1; then exit 1; fi
    [[ ! -e data/zerotier/.install-settings ]]
    mkdir -p data/zerotier/lost+found
    if printf '1\n%s\n%s\n%s\nn\n%s\n\n' "$port" "$occupied" "$files" "$address" |
        DOCKER_IMAGE=$candidate "$project/deploy.sh" >conflict.log 2>&1; then exit 1; fi
    if printf '1\nn\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh" >>conflict.log 2>&1; then exit 1; fi
    printf '1\ny\n%s\n%s\n%s\nn\n%s\n\n' "$port" "$api" "$files" "$address" |
        DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
    [[ $(docker port "$CONTAINER_NAME" "$api/tcp") == "127.0.0.1:$api" ]]
    password=$(docker exec "$CONTAINER_NAME" node /app/admin-password.js initial)
    [[ $password =~ ^[A-Za-z0-9_-]{20,}$ ]]
    [[ -z $(docker exec "$CONTAINER_NAME" node /app/admin-password.js initial) ]]
    [[ $(login "$api" "$password" -o /dev/null -w '%{http_code} %{redirect_url}' -c cookies) == \
        "302 http://127.0.0.1:$api/users/admin/password" ]]
    [[ $(curl --silent --show-error --max-time 5 --noproxy '*' -b cookies -o /dev/null \
        -w '%{http_code}' "http://127.0.0.1:$api/controller") == 200 ]]
    first=$(docker exec "$CONTAINER_NAME" sha256sum /var/lib/zerotier-one/identity.secret)
    docker rm -f "$CONTAINER_NAME" >/dev/null
    printf '1\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
    [[ $(docker exec "$CONTAINER_NAME" sha256sum /var/lib/zerotier-one/identity.secret) == "$first" ]]
    # Simulate a temporary storage error before the UI first reads its users.
    (
        passwd=/app/ztncui/src/etc/passwd
        docker exec "$CONTAINER_NAME" mv "$passwd" "$passwd.test-saved"
        trap 'docker exec "$CONTAINER_NAME" mv "$passwd.test-saved" "$passwd"' EXIT
        [[ $(login "$api" "$password" -o /dev/null -w '%{http_code}') == 500 ]]
        docker exec "$CONTAINER_NAME" /bin/sh /app/healthcheck.sh
    )
    [[ $(login "$api" "$password" -o /dev/null -w '%{http_code} %{redirect_url}') == \
        "302 http://127.0.0.1:$api/users/admin/password" ]]
    reset_output=$(printf '5\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh")
    reset_password=$(sed -n 's/^管理员 admin 的新密码：//p' <<< "$reset_output")
    [[ $reset_password =~ ^[A-Za-z0-9_-]{20,}$ && $reset_password != "$password" ]]
    [[ $(login "$api" "$password" -o /dev/null -w '%{redirect_url}') == "http://127.0.0.1:$api/login" ]]
    [[ $(login "$api" "$reset_password" -o /dev/null -w '%{redirect_url}') == \
        "http://127.0.0.1:$api/users/admin/password" ]]
    password_url="http://127.0.0.1:$api/users/admin/password"
    login "$api" "$reset_password" -o /dev/null -c cookies
    token=$(fetch_form -b cookies "$password_url")
    printf 'username=admin&password1=%s&password2=%s&_csrf=%s' "$password" "$password" "$token" | \
        curl --fail --silent --show-error --max-time 5 --noproxy '*' -b cookies --data-binary @- "$password_url" >/dev/null
    [[ $(login "$api" "$password" -o /dev/null -w '%{redirect_url}') == "http://127.0.0.1:$api/controller" ]]
    docker rm -f "$CONTAINER_NAME" >/dev/null
)
echo '首次安装、端口冲突纠正、管理登录、密码重置和容器丢失后的原地重装通过。'
mkdir -p data/zerotier/{one,config,ztncui,dist}
source "$project/deploy.sh"
ZT_PORT=$port API_PORT=$api FILE_PORT=$files ipv4=$address ipv6=::1
docker run -d --name "$CONTAINER_NAME" --restart unless-stopped \
    -p "$port:$port/tcp" -p "$port:$port/udp" \
    -p "127.0.0.1:$mapped_api:$api/tcp" -p "$address:$files:$files/tcp" \
    -e "IP_ADDR4=$ipv4" -e "IP_ADDR6=$ipv6" -e "ZT_PORT=$ZT_PORT" \
    -e "API_PORT=$API_PORT" -e "FILE_SERVER_PORT=$FILE_PORT" \
    -v "$DIST_PATH:/app/dist" -v "$ZTNCUI_PATH:/app/ztncui" \
    -v "$ZEROTIER_PATH/one:/var/lib/zerotier-one" -v "$CONFIG_PATH:/app/config" \
    "$legacy" >/dev/null
wait_ready "$CONTAINER_NAME"
published=$(docker port "$CONTAINER_NAME" | sort)
root_id=$(docker exec "$CONTAINER_NAME" sh -c "cut -d: -f1 /var/lib/zerotier-one/identity.public")
controller() {
    docker exec "$CONTAINER_NAME" sh -ec '
        port=$(cat /app/config/zerotier-one.port)
        token=$(cat /var/lib/zerotier-one/authtoken.secret)
        path=$1; shift
        curl -fsS -H "X-ZT1-Auth: $token" "$@" "http://127.0.0.1:$port/controller/network/$path"
    ' controller "$@"
}
network_id=$(controller "${root_id}______" -X POST -d '{"name":"upgrade-e2e","private":true,"v4AssignMode":{"zt":true},"ipAssignmentPools":[{"ipRangeStart":"10.242.250.10","ipRangeEnd":"10.242.250.40"}],"routes":[{"target":"10.242.250.0/24","via":null}]}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
docker run -d --name "$client" --cap-add NET_ADMIN --device /dev/net/tun \
    -v "$DIST_PATH:/artifacts:ro" --entrypoint sh "$legacy" -ec '
        cd /var/lib/zerotier-one
        [ -s ./planet ] || cp /artifacts/planet ./planet
        exec /usr/sbin/zerotier-one
    ' >/dev/null
client_cli() { docker exec "$client" /bak/zerotier-one/zerotier-cli "$@"; }
for ((i=0; i<40; i++)); do client_cli info >/dev/null 2>&1 && break; sleep 1; done
client_id=$(client_cli info | cut -d' ' -f3)
[[ $client_id =~ ^[0-9a-f]{10}$ ]]
controller "$network_id/member/$client_id" -X POST -d '{"authorized":true}' >/dev/null
client_cli join "$network_id" >/dev/null
connected() {
    for ((i=0; i<60; i++)); do
        if client_cli -j listnetworks 2>/dev/null | python3 -c '
import json,sys
nets=json.load(sys.stdin)
sys.exit(not any(n["id"]==sys.argv[1] and n["status"]=="OK" and n["assignedAddresses"] for n in nets))
' "$network_id" 2>/dev/null && client_cli -j listpeers 2>/dev/null | python3 -c '
import json,sys,time
recent=time.time()*1000-30000
peers=json.load(sys.stdin)
sys.exit(not any(p["address"]==sys.argv[1] and any(path["active"] and path["lastReceive"]>recent
             for path in p["paths"]) for p in peers))
' "$root_id" 2>/dev/null; then return 0; fi
        sleep 1
    done
    client_cli listnetworks
    return 1
}
fingerprint() {
    docker exec "$CONTAINER_NAME" sh -ec 'cd /var/lib/zerotier-one
        sha256sum identity.secret previous.c25519 current.c25519 /app/dist/planet /app/dist/*.moon'
}
password_fingerprint() {
    docker exec "$CONTAINER_NAME" sha256sum /app/ztncui/src/etc/passwd
}
connected
original=$(fingerprint)
legacy_password=$(password_fingerprint)
echo '旧版客户端已连接并获得地址。'
# Restart the same client from its existing configuration after upgrading.
printf '3\ny\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
[[ $(fingerprint) == "$original" ]]
[[ $(docker port "$CONTAINER_NAME" | sort) == "$published" ]]
rotated_password=$(password_fingerprint)
[[ $rotated_password != "$legacy_password" ]]
initial=$(docker exec "$CONTAINER_NAME" node /app/admin-password.js initial)
[[ $initial =~ ^[A-Za-z0-9_-]{20,}$ ]]
[[ $(login "$mapped_api" "$initial" -o /dev/null -w '%{http_code} %{redirect_url}') == \
    "302 http://127.0.0.1:$mapped_api/users/admin/password" ]]
docker restart "$client" >/dev/null
connected
controller "$network_id/member/$client_id" | python3 -c 'import json,sys;assert json.load(sys.stdin)["authorized"]'
printf '1\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
[[ $(fingerprint) == "$original" ]]
[[ $(password_fingerprint) == "$rotated_password" ]]
echo '原地升级和重复安装通过，原客户端仍获得网络授权。'
# An unhealthy candidate writes into both controller and download directories.
docker build -q --build-arg "SOURCE=$legacy" -t "$broken" - <<'DOCKERFILE' >/dev/null
ARG SOURCE
FROM ${SOURCE}
LABEL org.zerotier-planet.retry-safe="1"
LABEL org.zerotier-planet.secure-admin="1"
HEALTHCHECK --interval=1s --timeout=1s --retries=1 CMD exit 1
CMD ["sh","-c","echo bad >/app/dist/planet && touch /var/lib/zerotier-one/controller.d/failed-update && sleep 180"]
DOCKERFILE
bad_id=$(docker image inspect --format '{{.Id}}' "$broken")
if printf '3\ny\n' | DOCKER_IMAGE=$bad_id "$project/deploy.sh" >/dev/null; then
    echo '故障镜像升级意外成功。' >&2; exit 1
fi
[[ $(docker inspect --format '{{.Image}}' "$CONTAINER_NAME") == "$candidate" ]]
[[ $(fingerprint) == "$original" ]]
[[ $(password_fingerprint) == "$rotated_password" ]]
[[ $(docker port "$CONTAINER_NAME" | sort) == "$published" ]]
docker exec "$CONTAINER_NAME" test ! -e /var/lib/zerotier-one/controller.d/failed-update
docker restart "$client" >/dev/null
connected
echo '故障升级恢复了原镜像和完整数据，原客户端可以重新连接。'

docker rm -f "$CONTAINER_NAME" >/dev/null
printf '1\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
[[ $(docker port "$CONTAINER_NAME" | sort) == "$published" ]]
[[ $(fingerprint) == "$original" && $(password_fingerprint) == "$rotated_password" ]]
echo '容器丢失后的重装保留了宿主机端口绑定和管理员密码。'
