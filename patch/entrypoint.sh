#!/bin/sh

set -eu

ZEROTIER_PATH="/var/lib/zerotier-one"
APP_PATH="/app"
CONFIG_PATH="${APP_PATH}/config"
BACKUP_PATH="/bak"
ZTNCUI_PATH="${APP_PATH}/ztncui"
ZTNCUI_SRC_PATH="${ZTNCUI_PATH}/src"
DEFAULT_ZT_PORT="9994"

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

read_config_value() {
    if [ -f "$1" ]; then
        tr -d '\r\n' < "$1"
    fi
    return 0
}

moon_endpoint_port() {
    if [ -f "${ZEROTIER_PATH}/moon.json" ]; then
        jq -r '.roots[0].stableEndpoints[]? | capture("^(?<host>.*)/(?<port>[0-9]+)$")? | .port' "${ZEROTIER_PATH}/moon.json" 2>/dev/null | sed -n '1p'
    fi
    return 0
}

moon_endpoint_ip() {
    family="$1"
    if [ -f "${ZEROTIER_PATH}/moon.json" ]; then
        jq -r --arg family "${family}" '
            .roots[0].stableEndpoints[]?
            | capture("^(?<host>.*)/(?<port>[0-9]+)$")?
            | .host
            | select(if $family == "4" then test("^[0-9]+(\\.[0-9]+){3}$") else contains(":") end)
        ' "${ZEROTIER_PATH}/moon.json" 2>/dev/null | sed -n '1p'
    fi
    return 0
}

resolve_zt_port() {
    stored_port="$(read_config_value "${CONFIG_PATH}/zerotier-one.port")"
    moon_port="$(moon_endpoint_port)"
    requested_port="$(printf '%s' "${ZT_PORT:-}" | tr -d '\r\n')"

    if [ -n "${requested_port}" ]; then
        ZT_PORT="${requested_port}"
    elif [ -n "${stored_port}" ]; then
        ZT_PORT="${stored_port}"
    elif [ -n "${moon_port}" ]; then
        ZT_PORT="${moon_port}"
    else
        ZT_PORT="${DEFAULT_ZT_PORT}"
    fi
    export ZT_PORT
}

write_config() {
    mkdir -p "${CONFIG_PATH}"
    resolve_zt_port
    printf '%s\n' "${ZT_PORT}" > "${CONFIG_PATH}/zerotier-one.port"
    printf '%s\n' "${API_PORT}" > "${CONFIG_PATH}/ztncui.port"
}

sync_file_server_port() {
    mkdir -p "${CONFIG_PATH}"
    printf '%s\n' "${FILE_SERVER_PORT}" > "${CONFIG_PATH}/file_server.port"
    export FILE_SERVER_PORT
}

discover_ips() {
    ip_addr4_was_unset=0
    ip_addr6_was_unset=0
    if [ -z "${IP_ADDR4+x}" ]; then
        ip_addr4_was_unset=1
    fi
    if [ -z "${IP_ADDR6+x}" ]; then
        ip_addr6_was_unset=1
    fi

    IP_ADDR4="$(printf '%s' "${IP_ADDR4:-}" | tr -d '\r\n')"
    IP_ADDR6="$(printf '%s' "${IP_ADDR6:-}" | tr -d '\r\n')"

    if [ -z "${IP_ADDR4}" ] && [ -z "${IP_ADDR6}" ]; then
        IP_ADDR4="$(read_config_value "${CONFIG_PATH}/ip_addr4")"
        IP_ADDR6="$(read_config_value "${CONFIG_PATH}/ip_addr6")"

        if [ -z "${IP_ADDR4}" ]; then
            IP_ADDR4="$(moon_endpoint_ip 4)"
        fi
        if [ -z "${IP_ADDR6}" ]; then
            IP_ADDR6="$(moon_endpoint_ip 6)"
        fi

        if [ -z "${IP_ADDR4}" ] && [ "${ip_addr4_was_unset}" -eq 1 ]; then
            IP_ADDR4="$(curl -fsS https://ipv4.icanhazip.com/ || true)"
        fi
        if [ -z "${IP_ADDR6}" ] && [ "${ip_addr6_was_unset}" -eq 1 ]; then
            IP_ADDR6="$(curl -fsS https://ipv6.icanhazip.com/ || true)"
        fi
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

write_world_files() {
    endpoints="$1"

    jq --argjson newEndpoints "${endpoints}" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json
    mv temp.json moon.json

    rm -f ./*.moon
    ./zerotier-idtool genmoon moon.json
    mkdir -p moons.d
    rm -f ./moons.d/*.moon
    cp ./*.moon ./moons.d

    mkdir -p "${APP_PATH}/dist"
    generate_planet
    cp ./*.moon "${APP_PATH}/dist/"
}

refresh_zerotier_world_files() {
    cd "${ZEROTIER_PATH}"

    discover_ips
    printf '%s\n' "${IP_ADDR4}" > "${CONFIG_PATH}/ip_addr4"
    printf '%s\n' "${IP_ADDR6}" > "${CONFIG_PATH}/ip_addr6"

    endpoints="$(stable_endpoints_json)"
    current_endpoints="$(jq -c '.roots[0].stableEndpoints // []' moon.json 2>/dev/null || true)"

    if [ "${1:-}" = "force" ] || [ "${current_endpoints}" != "${endpoints}" ] || [ ! -f "${APP_PATH}/dist/planet" ]; then
        echo "Refreshing ZeroTier world files"
        write_world_files "${endpoints}"
        echo "mkmoonworld success!"
    else
        echo "ZeroTier world files are current"
    fi
}

init_zerotier_data() {
    echo "Initializing ZeroTier data"
    cp -r "${BACKUP_PATH}/zerotier-one/." "${ZEROTIER_PATH}/"

    cd "${ZEROTIER_PATH}"
    openssl rand -hex 16 > authtoken.secret
    ./zerotier-idtool generate identity.secret identity.public
    ./zerotier-idtool initmoon identity.public > moon.json
    refresh_zerotier_world_files force
}

check_zerotier() {
    mkdir -p "${ZEROTIER_PATH}"
    if [ "$(ls -A "${ZEROTIER_PATH}")" ]; then
        echo "${ZEROTIER_PATH} is not empty, starting directly"
        refresh_zerotier_world_files
    else
        init_zerotier_data
    fi
}

resolve_ztncui_password() {
    PASSWORD="${ZTNCUI_BOOTSTRAP_PASSWORD:-}"
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

write_ztncui_env() {
    mkdir -p "${ZTNCUI_SRC_PATH}"
    cd "${ZTNCUI_SRC_PATH}"
    tmp_env=".env.tmp.$$"
    if [ -f .env ]; then
        awk '
            BEGIN {
                managed["HTTP_PORT"] = 1
                managed["NODE_ENV"] = 1
                managed["HTTP_ALL_INTERFACES"] = 1
                managed["ZT_ADDR"] = 1
                managed["ZT_TOKEN"] = 1
            }
            /^[A-Za-z_][A-Za-z0-9_]*=/ {
                key = $0
                sub(/=.*/, "", key)
                if (key in managed) {
                    next
                }
            }
            { print }
        ' .env > "${tmp_env}"
    else
        : > "${tmp_env}"
    fi
    {
        echo "HTTP_PORT=${API_PORT}"
        echo 'NODE_ENV=production'
        echo "HTTP_ALL_INTERFACES=${ZTNCUI_HTTP_ALL_INTERFACES:-true}"
        echo "ZT_ADDR=localhost:${ZT_PORT}"
        echo "ZT_TOKEN=$(cat "${ZEROTIER_PATH}/authtoken.secret")"
    } >> "${tmp_env}"
    mv "${tmp_env}" .env
}

init_ztncui_data() {
    echo "Initializing ztncui data"
    cp -r "${BACKUP_PATH}/ztncui/." "${ZTNCUI_PATH}/"

    write_ztncui_env
    init_ztncui_password
    echo "ztncui configuration successful!"
}

check_ztncui() {
    mkdir -p "${ZTNCUI_PATH}"
    if [ "$(ls -A "${ZTNCUI_PATH}")" ]; then
        printf '%s\n' "${API_PORT}" > "${CONFIG_PATH}/ztncui.port"
        write_ztncui_env
        echo "${ZTNCUI_PATH} is not empty, starting directly"
    else
        init_ztncui_data
    fi
}

start_services() {
    echo "Start ztncui and zerotier"
    cd "${ZEROTIER_PATH}"
    ./zerotier-one -p"$(cat "${CONFIG_PATH}/zerotier-one.port")" -d || {
        echo "zerotier-one failed to start" >&2
        exit 1
    }

    node "${APP_PATH}/http_server.js" > "${APP_PATH}/server.log" 2>&1 &
    HTTP_SERVER_PID="$!"

    cd "${ZTNCUI_SRC_PATH}"
    npm start &
    wait "$!"
}

sync_file_server_port
write_config
check_zerotier
check_ztncui
start_services
