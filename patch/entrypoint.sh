#!/bin/sh

set -eu

ZEROTIER_PATH="/var/lib/zerotier-one"
APP_PATH="/app"
CONFIG_PATH="${APP_PATH}/config"
BACKUP_PATH="/bak"
ZTNCUI_PATH="${APP_PATH}/ztncui"
ZTNCUI_SRC_PATH="${ZTNCUI_PATH}/src"
FILE_KEY_PLACEHOLDER="REPLACE_WITH_OPENSSL_RAND_HEX_32"
IPV4_PLACEHOLDER="YOUR_PUBLIC_IPV4"
IPV6_PLACEHOLDER="YOUR_PUBLIC_IPV6"
PLANET_WORLD_ID="0000000008eac90a"

start() {
    echo "Start ztncui and zerotier"
    cd "$ZEROTIER_PATH" && ./zerotier-one -p"$(cat "${CONFIG_PATH}/zerotier-one.port")" -d || exit 1
    nohup node "${APP_PATH}/http_server.js" > "${APP_PATH}/server.log" 2>&1 &
    cd "$ZTNCUI_SRC_PATH" && npm start || exit 1
}

persist_file_key() {
    mkdir -p "$CONFIG_PATH"
    if [ -n "${FILE_KEY:-}" ] && [ "${FILE_KEY}" != "$FILE_KEY_PLACEHOLDER" ]; then
        (umask 077 && printf '%s\n' "$FILE_KEY" > "${CONFIG_PATH}/file_server.key")
    fi
}

check_file_server() {
    mkdir -p "$CONFIG_PATH"
    persist_file_key
    printf '%s\n' "${FILE_SERVER_PORT}" > "${CONFIG_PATH}/file_server.port"
    export FILE_SERVER_PORT
    echo "${FILE_SERVER_PORT}"
}

detect_public_ip() {
    local version="$1"
    local endpoint="https://ipv${version}.icanhazip.com/"

    curl -fsS --max-time 10 "$endpoint" 2>/dev/null | tr -d '\r\n' || true
}

normalize_ip_value() {
    local value="$1"
    local placeholder="$2"

    if [ "$value" = "$placeholder" ]; then
        printf ''
        return
    fi

    printf '%s' "$value" | tr -d '\r\n'
}

clear_directory() {
    local path="$1"

    if [ -z "$path" ] || [ "$path" = "/" ]; then
        echo "Refusing to clear unsafe directory: $path" >&2
        exit 1
    fi

    mkdir -p "$path"
    rm -rf "$path"/* "$path"/.[!.]* "$path"/..?*
}

clear_generated_dist() {
    mkdir -p "${APP_PATH}/dist/"
    rm -f "${APP_PATH}/dist/planet" "${APP_PATH}/dist/"*.moon
}

init_zerotier_data() {
    echo "Initializing ZeroTier data"
    mkdir -p "$CONFIG_PATH" "$ZEROTIER_PATH"
    printf '%s\n' "initializing" > "${CONFIG_PATH}/zerotier-one.init-status"
    printf '%s\n' "${ZT_PORT}" > "${CONFIG_PATH}/zerotier-one.port"
    cp -r "${BACKUP_PATH}/zerotier-one/." "$ZEROTIER_PATH"

    cd "$ZEROTIER_PATH"
    openssl rand -hex 16 > authtoken.secret
    ./zerotier-idtool generate identity.secret identity.public
    ./zerotier-idtool initmoon identity.public > moon.json

    IP_ADDR4="$(normalize_ip_value "${IP_ADDR4:-}" "$IPV4_PLACEHOLDER")"
    IP_ADDR6="$(normalize_ip_value "${IP_ADDR6:-}" "$IPV6_PLACEHOLDER")"
    IP_ADDR4="${IP_ADDR4:-$(detect_public_ip 4)}"
    IP_ADDR6="${IP_ADDR6:-$(detect_public_ip 6)}"

    echo "IP_ADDR4=$IP_ADDR4"
    echo "IP_ADDR6=$IP_ADDR6"
    ZT_PORT="$(cat "${CONFIG_PATH}/zerotier-one.port")"
    echo "ZT_PORT=$ZT_PORT"

    if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then
        stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"
    elif [ -n "$IP_ADDR4" ]; then
        stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"
    elif [ -n "$IP_ADDR6" ]; then
        stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"
    else
        echo "IP_ADDR4 and IP_ADDR6 are both empty!"
        exit 1
    fi

    printf '%s\n' "$IP_ADDR4" > "${CONFIG_PATH}/ip_addr4"
    printf '%s\n' "$IP_ADDR6" > "${CONFIG_PATH}/ip_addr6"
    echo "stableEndpoints=$stableEndpoints"

    jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json && mv temp.json moon.json
    ./zerotier-idtool genmoon moon.json && mkdir -p moons.d && cp ./*.moon ./moons.d

    jq --arg planetId "$PLANET_WORLD_ID" '.worldType = "planet" | .id = $planetId' moon.json > planet.json
    rm -f "${PLANET_WORLD_ID}.moon"
    if ! ./zerotier-idtool genmoon planet.json; then
        echo "planet generation failed!"
        exit 1
    fi
    if [ ! -f "${PLANET_WORLD_ID}.moon" ]; then
        echo "planet generation did not create ${PLANET_WORLD_ID}.moon"
        exit 1
    fi

    clear_generated_dist
    mv "${PLANET_WORLD_ID}.moon" "${APP_PATH}/dist/planet"
    cp ./moons.d/*.moon "${APP_PATH}/dist/"
    printf '%s\n' "complete" > "${CONFIG_PATH}/zerotier-one.init-status"
    echo "planet generation success!"
}

check_zerotier() {
    local requested_port="${ZT_PORT}"
    local stored_port
    local init_status_file="${CONFIG_PATH}/zerotier-one.init-status"
    local init_status=""

    mkdir -p "$CONFIG_PATH" "$ZEROTIER_PATH"
    if [ "$(ls -A "$ZEROTIER_PATH")" ]; then
        echo "$ZEROTIER_PATH is not empty, starting directly"
        if [ -f "$init_status_file" ]; then
            init_status="$(tr -d '\r\n' < "$init_status_file")"
        fi
        if [ "$init_status" = "initializing" ]; then
            echo "Incomplete ZeroTier initialization detected, retrying setup"
            clear_directory "$ZEROTIER_PATH"
            init_zerotier_data
            return
        fi

        if [ ! -f "${CONFIG_PATH}/zerotier-one.port" ]; then
            echo "Existing ZeroTier data requires ${CONFIG_PATH}/zerotier-one.port." >&2
            echo "Restore the config volume or recreate ZeroTier data to regenerate planet/moon files." >&2
            exit 1
        fi

        stored_port="$(tr -d '\r\n' < "${CONFIG_PATH}/zerotier-one.port")"
        if [ -z "$stored_port" ]; then
            echo "Existing ZeroTier data has an empty saved ZT_PORT in ${CONFIG_PATH}/zerotier-one.port." >&2
            echo "Restore the config volume or recreate ZeroTier data to regenerate planet/moon files." >&2
            exit 1
        elif [ "$stored_port" != "$requested_port" ]; then
            echo "ZT_PORT changed from $stored_port to $requested_port for existing ZeroTier data." >&2
            echo "Recreate the ZeroTier data directory to change this port." >&2
            exit 1
        else
            ZT_PORT="$stored_port"
        fi
        export ZT_PORT
    else
        init_zerotier_data
    fi
}

set_env_value() {
    local env_file="$1"
    local key="$2"
    local value="$3"
    local tmp

    tmp="$(mktemp "${env_file}.XXXXXX")"
    if [ -f "$env_file" ]; then
        grep -v "^${key}=" "$env_file" > "$tmp" || true
    else
        : > "$tmp"
    fi

    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$env_file"
}

write_ztncui_env() {
    local env_file="${ZTNCUI_SRC_PATH}/.env"

    TOKEN="$(cat "${ZEROTIER_PATH}/authtoken.secret")"
    set_env_value "$env_file" "HTTP_PORT" "${API_PORT}"
    set_env_value "$env_file" "NODE_ENV" "production"
    set_env_value "$env_file" "HTTP_ALL_INTERFACES" "true"
    set_env_value "$env_file" "ZT_ADDR" "localhost:${ZT_PORT}"
    set_env_value "$env_file" "ZT_TOKEN" "$TOKEN"
}

init_ztncui_data() {
    echo "Initializing ztncui data"
    cp -r "${BACKUP_PATH}/ztncui/." "$ZTNCUI_PATH"

    echo "Configuring ztncui"
    cp -v "${ZTNCUI_SRC_PATH}/etc/default.passwd" "${ZTNCUI_SRC_PATH}/etc/passwd"
    echo "ztncui configuration successful!"
}

check_ztncui() {
    mkdir -p "$CONFIG_PATH" "$ZTNCUI_PATH"
    printf '%s\n' "${API_PORT}" > "${CONFIG_PATH}/ztncui.port"

    if [ "$(ls -A "$ZTNCUI_PATH")" ]; then
        echo "$ZTNCUI_PATH is not empty, starting directly"
    else
        init_ztncui_data
    fi

    write_ztncui_env
}

check_file_server
check_zerotier
check_ztncui
start
