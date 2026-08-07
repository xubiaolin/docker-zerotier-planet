#!/usr/bin/env bash

set -Eeuo pipefail

env_value() {
    local key=$1
    local fallback=${2:-}
    local line value
    if [[ -f "$ENV_FILE" ]]; then
        line=$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" | tail -n 1 || true)
        if [[ -n "$line" ]]; then
            value=${line#*=}
            value=${value%$'\r'}
            if [[ "$value" == \"*\" && "$value" == *\" ]]; then
                value=${value:1:${#value}-2}
            elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
                value=${value:1:${#value}-2}
            fi
            printf '%s' "$value"
            return 0
        fi
    fi
    printf '%s' "$fallback"
}

set_env_value() {
    local key=$1
    local value=$2
    local temporary
    temporary=$(mktemp "$PROJECT_ROOT/.env.XXXXXX")
    awk -v key="$key" -v value="$value" '
        BEGIN { found = 0 }
        $0 ~ "^[[:space:]]*" key "=" { print key "=" value; found = 1; next }
        { print }
        END { if (!found) print key "=" value }
    ' "$ENV_FILE" >"$temporary"
    chmod 0600 "$temporary"
    mv -f "$temporary" "$ENV_FILE"
}

prompt_value() {
    local key=$1
    local prompt=$2
    local fallback=$3
    local current value
    current=$(env_value "$key" "$fallback")
    read -r -p "$prompt [$current]: " value
    set_env_value "$key" "${value:-$current}"
}

import_legacy_config() {
    local configured data_path key file value
    configured=$(env_value DATA_DIR './data/zerotier')
    if [[ "$configured" = /* ]]; then
        data_path=$(realpath -m -- "$configured")
    else
        data_path=$(realpath -m -- "$PROJECT_ROOT/$configured")
    fi
    while read -r key file; do
        if [[ -s "$data_path/config/$file" ]]; then
            IFS= read -r value <"$data_path/config/$file" || true
            set_env_value "$key" "${value%$'\r'}"
        fi
    done <<'EOF'
ZT_PORT zerotier-one.port
API_PORT ztncui.port
FILE_SERVER_PORT file_server.port
IP_ADDR4 ip_addr4
IP_ADDR6 ip_addr6
EOF
}

ensure_env_file() {
    local prompt=${1:-}
    local created=0
    if [[ ! -f "$ENV_FILE" ]]; then
        install -m 0600 "$PROJECT_ROOT/.env.example" "$ENV_FILE"
        created=1
        log info "已创建 $ENV_FILE"
    fi

    if ((created == 1)); then
        import_legacy_config
    fi

    if [[ "$prompt" == prompt && -t 0 && "${NON_INTERACTIVE:-0}" != 1 ]]; then
        prompt_value ZT_PORT 'ZeroTier 端口' 9994
        prompt_value API_PORT '管理界面端口' 3443
        prompt_value FILE_SERVER_PORT '文件下载端口' 3000
        prompt_value IP_ADDR4 '公网 IPv4（留空则自动探测）' ''
        prompt_value IP_ADDR6 '公网 IPv6（可留空）' ''
    fi
}
