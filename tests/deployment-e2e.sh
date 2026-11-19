#!/usr/bin/env bash
# Run against a locally built candidate and the published pre-refactor image.
# Creates a private deployment, an authorized client and a failed update.
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd -P)
candidate=$(docker image inspect --format '{{.Id}}' "${1:?supply the locally built image}")
legacy=${2:-xubiaolin/zerotier-planet@sha256:55611f7107fb48c33ecffa132a694b6c3f23cdb61f2317def309447d24d34fdb}
docker image inspect "$legacy" >/dev/null 2>&1 || docker pull "$legacy" >/dev/null
work=$(mktemp -d)
cd "$work"
export CONTAINER_NAME=planet-e2e-$$ DOCKER_IMAGE=$legacy
client=$CONTAINER_NAME-client
broken=planet-failed-upgrade-$$:test
cleanup() {
    docker rm -fv "$CONTAINER_NAME" "$client" >/dev/null 2>&1 || true
    docker image rm "$broken" >/dev/null 2>&1 || true
    docker run --rm --network none -v "$work:/cleanup" --entrypoint sh "$legacy" \
        -c 'find /cleanup -mindepth 1 -maxdepth 1 -exec rm -rf {} +' >/dev/null
    rmdir "$work"
}
trap cleanup EXIT
# Reserve distinct test ports without using the project's default listeners.
read -r port api files < <(python3 - <<'PY'
import socket
sockets = [socket.socket() for i in range(3)]
for s in sockets:
    s.bind(('', 0))
print(*(s.getsockname()[1] for s in sockets))
PY
)
address=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')
# Publish the temporary management and download endpoints only on Docker's bridge.
export TEST_DOCKER=$(command -v docker) TEST_BRIDGE=$address
mkdir test-bin
cat >test-bin/docker <<'WRAPPER'
#!/usr/bin/env bash
args=()
while (( $# )); do
    case "$1" in
        -p) args+=(-p "$TEST_BRIDGE:$2"); shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
exec "$TEST_DOCKER" "${args[@]}"
WRAPPER
chmod +x test-bin/docker
export PATH="$PWD/test-bin:$PATH"
# Exercise first installation through the menu, with the same ports reused
# later by the separate legacy fixture after this container has been removed.
mkdir first-install
(
    cd first-install
    if printf '1\n%s\n%s\n%s\nn\ninvalid IP\n\n' "$port" "$api" "$files" |
        DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null 2>&1; then exit 1; fi
    [[ ! -e data/zerotier/.install-settings ]]
    printf '1\n%s\n%s\n%s\nn\n%s\n\n' "$port" "$api" "$files" "$address" |
        DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
    first=$(docker exec "$CONTAINER_NAME" sha256sum /var/lib/zerotier-one/identity.secret)
    docker rm -f "$CONTAINER_NAME" >/dev/null
    printf '1\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
    [[ $(docker exec "$CONTAINER_NAME" sha256sum /var/lib/zerotier-one/identity.secret) == "$first" ]]
    docker rm -f "$CONTAINER_NAME" >/dev/null
)
echo '首次安装、无效参数纠正、容器丢失后的原地重装通过。'
mkdir -p data/zerotier/{one,config,ztncui,dist}
source "$project/deploy.sh"
ZT_PORT=$port API_PORT=$api FILE_PORT=$files ipv4=$address ipv6=::1
run_container "$legacy" >/dev/null
wait_ready "$CONTAINER_NAME"
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
        sha256sum identity.secret previous.c25519 current.c25519 /app/dist/planet /app/dist/*.moon /app/ztncui/src/etc/passwd'
}
connected
original=$(fingerprint)
echo '旧版客户端已连接并获得地址。'
# Restart the same client from its existing configuration after upgrading.
printf '3\ny\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
[[ $(fingerprint) == "$original" ]]
docker restart "$client" >/dev/null
connected
controller "$network_id/member/$client_id" | python3 -c 'import json,sys;assert json.load(sys.stdin)["authorized"]'
printf '1\n' | DOCKER_IMAGE=$candidate "$project/deploy.sh" >/dev/null
[[ $(fingerprint) == "$original" ]]
echo '原地升级和重复安装通过，原客户端仍获得网络授权。'
# An unhealthy candidate writes into both controller and download directories.
docker build -q --build-arg "SOURCE=$legacy" -t "$broken" - <<'DOCKERFILE' >/dev/null
ARG SOURCE
FROM ${SOURCE}
LABEL org.zerotier-planet.retry-safe="1"
HEALTHCHECK --interval=1s --timeout=1s --retries=1 CMD exit 1
CMD ["sh","-c","echo bad >/app/dist/planet && touch /var/lib/zerotier-one/controller.d/failed-update && sleep 180"]
DOCKERFILE
bad_id=$(docker image inspect --format '{{.Id}}' "$broken")
if printf '3\ny\n' | DOCKER_IMAGE=$bad_id "$project/deploy.sh" >/dev/null; then
    echo '故障镜像升级意外成功。' >&2; exit 1
fi
[[ $(docker inspect --format '{{.Image}}' "$CONTAINER_NAME") == "$candidate" ]]
[[ $(fingerprint) == "$original" ]]
docker exec "$CONTAINER_NAME" test ! -e /var/lib/zerotier-one/controller.d/failed-update
docker restart "$client" >/dev/null
connected
echo '故障升级恢复了原镜像和完整数据，原客户端可以重新连接。'
