#!/bin/sh

set -eu

load_value() {
    variable_name=$1
    persisted_file=$2
    default_value=$3

    eval "environment_value=\${${variable_name}:-}"
    persisted_value=$(read_first_line "$persisted_file")

    if [ -n "$environment_value" ]; then
        resolved_value=$environment_value
    elif [ -n "$persisted_value" ]; then
        resolved_value=$persisted_value
    else
        resolved_value=$default_value
    fi

    export "$variable_name=$resolved_value"
}

assert_immutable_value() {
    name=$1
    file=$2
    requested=$3
    persisted=$(read_first_line "$file")

    if [ -n "$persisted" ] && [ "$persisted" != "$requested" ] && [ "${PLANET_REGENERATE:-0}" != "1" ]; then
        die "$name changed from '$persisted' to '$requested'; run deploy.sh reconfigure"
    fi
}

discover_public_addresses() {
    if [ -z "$IP_ADDR4" ]; then
        IP_ADDR4=$(curl --fail --silent --show-error --max-time 8 https://ipv4.icanhazip.com 2>/dev/null || true)
        IP_ADDR4=$(printf '%s' "$IP_ADDR4" | tr -d '\r\n')
    fi
    if [ -z "$IP_ADDR6" ]; then
        IP_ADDR6=$(curl --fail --silent --show-error --max-time 8 https://ipv6.icanhazip.com 2>/dev/null || true)
        IP_ADDR6=$(printf '%s' "$IP_ADDR6" | tr -d '\r\n')
    fi
    export IP_ADDR4 IP_ADDR6
}

is_ip_version() {
    address=$1
    version=$2
    node -e 'process.exit(require("node:net").isIP(process.argv[1]) === Number(process.argv[2]) ? 0 : 1)' "$address" "$version"
}

load_config() {
    mkdir -p "$CONFIG_PATH" "$DIST_PATH" "$ZTNCUI_STATE_PATH" "$ZEROTIER_PATH"

    load_value ZT_PORT "$CONFIG_PATH/zerotier-one.port" 9994
    load_value API_PORT "$CONFIG_PATH/ztncui.port" 3443
    load_value FILE_SERVER_PORT "$CONFIG_PATH/file_server.port" 3000
    load_value IP_ADDR4 "$CONFIG_PATH/ip_addr4" ''
    load_value IP_ADDR6 "$CONFIG_PATH/ip_addr6" ''

    is_valid_port "$ZT_PORT" || die "invalid ZT_PORT: $ZT_PORT"
    is_valid_port "$API_PORT" || die "invalid API_PORT: $API_PORT"
    is_valid_port "$FILE_SERVER_PORT" || die "invalid FILE_SERVER_PORT: $FILE_SERVER_PORT"
    if [ "$ZT_PORT" = "$API_PORT" ] || [ "$ZT_PORT" = "$FILE_SERVER_PORT" ] || [ "$API_PORT" = "$FILE_SERVER_PORT" ]; then
        die "ZT_PORT, API_PORT, and FILE_SERVER_PORT must be distinct"
    fi

    discover_public_addresses
    [ -n "$IP_ADDR4" ] || [ -n "$IP_ADDR6" ] || die "no public IPv4 or IPv6 address is configured"
    [ -z "$IP_ADDR4" ] || is_ip_version "$IP_ADDR4" 4 || die "invalid IP_ADDR4: $IP_ADDR4"
    [ -z "$IP_ADDR6" ] || is_ip_version "$IP_ADDR6" 6 || die "invalid IP_ADDR6: $IP_ADDR6"

    assert_immutable_value ZT_PORT "$CONFIG_PATH/zerotier-one.port" "$ZT_PORT"
    assert_immutable_value IP_ADDR4 "$CONFIG_PATH/ip_addr4" "$IP_ADDR4"
    assert_immutable_value IP_ADDR6 "$CONFIG_PATH/ip_addr6" "$IP_ADDR6"
}

persist_config() {
    printf '%s\n' "$ZT_PORT" | atomic_write "$CONFIG_PATH/zerotier-one.port" 0600
    printf '%s\n' "$API_PORT" | atomic_write "$CONFIG_PATH/ztncui.port" 0600
    printf '%s\n' "$FILE_SERVER_PORT" | atomic_write "$CONFIG_PATH/file_server.port" 0600
    printf '%s\n' "$IP_ADDR4" | atomic_write "$CONFIG_PATH/ip_addr4" 0600
    printf '%s\n' "$IP_ADDR6" | atomic_write "$CONFIG_PATH/ip_addr6" 0600
}
