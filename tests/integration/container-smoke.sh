#!/usr/bin/env bash

set -Eeuo pipefail

IMAGE=${IMAGE:-zerotier-planet:test}
CONTAINER_NAME="planet-smoke-$RANDOM-$$"
TEST_ROOT=$(mktemp -d)
BACKUP_FILE=$(mktemp)
TEST_IP=203.0.113.10

cleanup() {
    docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker run --rm --volume "$TEST_ROOT:/cleanup" --entrypoint sh "$IMAGE" \
        -c 'chmod -R a+rwX /cleanup' >/dev/null 2>&1 || true
    rm -rf "$TEST_ROOT"
    rm -f "$BACKUP_FILE"
}
trap cleanup EXIT

mkdir -p "$TEST_ROOT"/{config,dist,ztncui,one}

start_container() {
    docker run --detach \
        --name "$CONTAINER_NAME" \
        --env IP_ADDR4="$TEST_IP" \
        --env ZT_PORT=19994 \
        --env API_PORT=13443 \
        --env FILE_SERVER_PORT=13000 \
        --read-only \
        --security-opt no-new-privileges:true \
        --tmpfs /run \
        --tmpfs /tmp \
        --volume "$TEST_ROOT/config:/app/config" \
        --volume "$TEST_ROOT/dist:/app/dist" \
        --volume "$TEST_ROOT/ztncui:/app/ztncui" \
        --volume "$TEST_ROOT/one:/var/lib/zerotier-one" \
        "$IMAGE" >/dev/null
}

wait_healthy() {
    local status
    for _ in $(seq 1 80); do
        status=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME")
        [[ "$status" == healthy ]] && return 0
        [[ "$status" == unhealthy ]] && docker logs "$CONTAINER_NAME" && return 1
        sleep 3
    done
    docker logs "$CONTAINER_NAME"
    return 1
}

start_container
wait_healthy

docker exec "$CONTAINER_NAME" test -s /app/dist/planet
docker exec "$CONTAINER_NAME" sh -c "find /app/dist -maxdepth 1 -type f -name '*.moon' | grep -q ."
docker exec "$CONTAINER_NAME" test -s /app/config/file_server.key
login_redirect=$(docker exec "$CONTAINER_NAME" sh -c \
    'password=$(cat /app/config/ztncui.initial-password); curl -sS -o /dev/null -w "%{redirect_url}" --data-urlencode username=admin --data-urlencode "password=$password" http://127.0.0.1:13443/login')
[[ "$login_redirect" == */controller ]]
docker exec "$CONTAINER_NAME" sh -c \
    'key=$(cat /app/config/file_server.key); test -n "$(curl -fsS -H "Authorization: Bearer $key" http://127.0.0.1:13000/planet)"'
identity_hash=$(docker exec "$CONTAINER_NAME" sha256sum /var/lib/zerotier-one/identity.secret | cut -d ' ' -f 1)
key_hash=$(docker exec "$CONTAINER_NAME" sha256sum /app/config/file_server.key | cut -d ' ' -f 1)
docker run --rm --volume "$TEST_ROOT:/source:ro" --entrypoint tar "$IMAGE" -C /source -czf - . >"$BACKUP_FILE"
tar -tzf "$BACKUP_FILE" './one/identity.secret' >/dev/null

docker restart "$CONTAINER_NAME" >/dev/null
sleep 10
[[ "$identity_hash" == "$(docker exec "$CONTAINER_NAME" sha256sum /var/lib/zerotier-one/identity.secret | cut -d ' ' -f 1)" ]]
[[ "$key_hash" == "$(docker exec "$CONTAINER_NAME" sha256sum /app/config/file_server.key | cut -d ' ' -f 1)" ]]

admin_hash=$(docker exec "$CONTAINER_NAME" sha256sum /app/ztncui/state/etc/passwd | cut -d ' ' -f 1)
planet_hash=$(docker exec "$CONTAINER_NAME" sha256sum /app/dist/planet | cut -d ' ' -f 1)
docker rm --force "$CONTAINER_NAME" >/dev/null
TEST_IP=203.0.113.11
docker run --rm \
    --env IP_ADDR4="$TEST_IP" \
    --env ZT_PORT=19994 \
    --env API_PORT=13443 \
    --env FILE_SERVER_PORT=13000 \
    --env PLANET_REGENERATE=1 \
    --read-only \
    --security-opt no-new-privileges:true \
    --tmpfs /run \
    --tmpfs /tmp \
    --volume "$TEST_ROOT/config:/app/config" \
    --volume "$TEST_ROOT/dist:/app/dist" \
    --volume "$TEST_ROOT/ztncui:/app/ztncui" \
    --volume "$TEST_ROOT/one:/var/lib/zerotier-one" \
    "$IMAGE" true
start_container
wait_healthy
[[ "$identity_hash" == "$(docker exec "$CONTAINER_NAME" sha256sum /var/lib/zerotier-one/identity.secret | cut -d ' ' -f 1)" ]]
[[ "$planet_hash" != "$(docker exec "$CONTAINER_NAME" sha256sum /app/dist/planet | cut -d ' ' -f 1)" ]]
[[ "$admin_hash" == "$(docker exec "$CONTAINER_NAME" sha256sum /app/ztncui/state/etc/passwd | cut -d ' ' -f 1)" ]]

docker rm --force "$CONTAINER_NAME" >/dev/null
docker run --rm --volume "$TEST_ROOT:/data" --entrypoint sh "$IMAGE" -c \
    'mkdir -p /data/ztncui/src && mv /data/ztncui/state/etc /data/ztncui/src/etc && rmdir /data/ztncui/state'
start_container
wait_healthy
[[ "$admin_hash" == "$(docker exec "$CONTAINER_NAME" sha256sum /app/ztncui/state/etc/passwd | cut -d ' ' -f 1)" ]]
