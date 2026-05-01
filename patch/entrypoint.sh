#!/bin/sh

set -eu

ZEROTIER_PATH="/var/lib/zerotier-one"
APP_PATH="/app"
CONFIG_PATH="${APP_PATH}/config"
BACKUP_PATH="/bak"
ZTNCUI_PATH="${APP_PATH}/ztncui"
ZTNCUI_SRC_PATH="${ZTNCUI_PATH}/src"

HTTP_SERVER_PID=""
ZEROTIER_PID=""

cleanup() {
    if [ -n "${HTTP_SERVER_PID}" ]; then
        kill "${HTTP_SERVER_PID}" 2>/dev/null || true
    fi
    if [ -n "${ZEROTIER_PID}" ]; then
        kill "${ZEROTIER_PID}" 2>/dev/null || true
    fi
}
trap cleanup INT TERM EXIT

write_config() {
    mkdir -p "${CONFIG_PATH}"
    printf '%s\n' "${ZT_PORT}" > "${CONFIG_PATH}/zerotier-one.port"
    printf '%s\n' "${API_PORT}" > "${CONFIG_PATH}/ztncui.port"
}

read_file_server_port() {
    mkdir -p "${CONFIG_PATH}"
    if [ ! -f "${CONFIG_PATH}/file_server.port" ]; then
        printf '%s\n' "${FILE_SERVER_PORT}" > "${CONFIG_PATH}/file_server.port"
    else
        FILE_SERVER_PORT="$(cat "${CONFIG_PATH}/file_server.port")"
    fi
    export FILE_SERVER_PORT
}

discover_ips() {
    if [ -z "${IP_ADDR4+x}" ]; then
        IP_ADDR4="$(curl -fsS https://ipv4.icanhazip.com/ || true)"
    fi
    if [ -z "${IP_ADDR6+x}" ]; then
        IP_ADDR6="$(curl -fsS https://ipv6.icanhazip.com/ || true)"
    fi

    IP_ADDR4="$(printf '%s' "${IP_ADDR4:-}" | tr -d '\r\n')"
    IP_ADDR6="$(printf '%s' "${IP_ADDR6:-}" | tr -d '\r\n')"
    export IP_ADDR4 IP_ADDR6
}

stable_endpoints_json() {
    if [ -n "${IP_ADDR4}" ] && [ -n "${IP_ADDR6}" ]; then
        printf '["%s/%s","%s/%s"]' "${IP_ADDR4}" "${ZT_PORT}" "${IP_ADDR6}" "${ZT_PORT}"
    elif [ -n "${IP_ADDR4}" ]; then
        printf '["%s/%s"]' "${IP_ADDR4}" "${ZT_PORT}"
    elif [ -n "${IP_ADDR6}" ]; then
        printf '["%s/%s"]' "${IP_ADDR6}" "${ZT_PORT}"
    else
        echo "IP_ADDR4 and IP_ADDR6 are both empty!" >&2
        exit 1
    fi
}

generate_planet() {
    jq '.worldType = "planet" | .id = "8eac90a"' moon.json > planet.json
    ./zerotier-idtool genmoon planet.json
    mv 0000000008eac90a.moon "${APP_PATH}/dist/planet"
}

init_zerotier_data() {
    echo "Initializing ZeroTier data"
    cp -r "${BACKUP_PATH}/zerotier-one/." "${ZEROTIER_PATH}/"

    cd "${ZEROTIER_PATH}"
    openssl rand -hex 16 > authtoken.secret
    ./zerotier-idtool generate identity.secret identity.public
    ./zerotier-idtool initmoon identity.public > moon.json

    discover_ips
    printf '%s\n' "${IP_ADDR4}" > "${CONFIG_PATH}/ip_addr4"
    printf '%s\n' "${IP_ADDR6}" > "${CONFIG_PATH}/ip_addr6"

    endpoints="$(stable_endpoints_json)"
    jq --argjson newEndpoints "${endpoints}" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json
    mv temp.json moon.json

    ./zerotier-idtool genmoon moon.json
    mkdir -p moons.d
    cp ./*.moon ./moons.d

    mkdir -p "${APP_PATH}/dist"
    generate_planet
    cp ./*.moon "${APP_PATH}/dist/"
    echo "mkmoonworld success!"
}

check_zerotier() {
    mkdir -p "${ZEROTIER_PATH}"
    if [ "$(ls -A "${ZEROTIER_PATH}")" ]; then
        echo "${ZEROTIER_PATH} is not empty, starting directly"
    else
        init_zerotier_data
    fi
}

resolve_ztncui_password() {
    PASSWORD="${ZTNCUI_BOOTSTRAP_PASSWORD:-${ZTNCUI_PASSWORD:-${ZTNCUI_PASSWD:-}}}"
    if [ -n "${ZTNCUI_BOOTSTRAP_PASSWORD_FILE:-}" ]; then
        if [ ! -f "${ZTNCUI_BOOTSTRAP_PASSWORD_FILE}" ]; then
            echo "ZTNCUI_BOOTSTRAP_PASSWORD_FILE does not exist" >&2
            exit 1
        fi
        PASSWORD="$(cat "${ZTNCUI_BOOTSTRAP_PASSWORD_FILE}")"
    fi

    if [ -z "${PASSWORD}" ]; then
        PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
        umask 077
        printf '%s\n' "${PASSWORD}" > "${CONFIG_PATH}/ztncui.initial-password"
        chmod 600 "${CONFIG_PATH}/ztncui.initial-password"
        echo "Generated a unique ztncui credential; retrieve it from /app/config/ztncui.initial-password"
    else
        rm -f "${CONFIG_PATH}/ztncui.initial-password"
        echo "Using operator-provided ztncui bootstrap password"
    fi
    export PASSWORD
}

init_ztncui_password() {
    resolve_ztncui_password
    ZTNCUI_ADMIN_PASSWORD="${PASSWORD}" node "${APP_PATH}/ztncui_admin.js"
    unset PASSWORD ZTNCUI_ADMIN_PASSWORD
}

init_ztncui_data() {
    echo "Initializing ztncui data"
    cp -r "${BACKUP_PATH}/ztncui/." "${ZTNCUI_PATH}/"

    cd "${ZTNCUI_SRC_PATH}"
    {
        echo "HTTP_PORT=${API_PORT}"
        echo 'NODE_ENV=production'
        echo "HTTP_ALL_INTERFACES=${ZTNCUI_HTTP_ALL_INTERFACES:-true}"
        echo "ZT_ADDR=localhost:${ZT_PORT}"
        echo "ZT_TOKEN=$(cat "${ZEROTIER_PATH}/authtoken.secret")"
    } > .env
    init_ztncui_password
    echo "ztncui configuration successful!"
}

check_ztncui() {
    mkdir -p "${ZTNCUI_PATH}"
    if [ "$(ls -A "${ZTNCUI_PATH}")" ]; then
        printf '%s\n' "${API_PORT}" > "${CONFIG_PATH}/ztncui.port"
        echo "${ZTNCUI_PATH} is not empty, starting directly"
    else
        init_ztncui_data
    fi
}

start_services() {
    echo "Start ztncui and zerotier"
    cd "${ZEROTIER_PATH}"
    ./zerotier-one -p"$(cat "${CONFIG_PATH}/zerotier-one.port")" -d &
    ZEROTIER_PID="$!"

    node "${APP_PATH}/http_server.js" > "${APP_PATH}/server.log" 2>&1 &
    HTTP_SERVER_PID="$!"

    cd "${ZTNCUI_SRC_PATH}"
    npm start &
    wait "$!"
}

read_file_server_port
write_config
check_zerotier
check_ztncui
start_services
