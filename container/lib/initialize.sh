#!/bin/sh

set -eu

ensure_file_server_key() {
    key_file="$CONFIG_PATH/file_server.key"
    if [ ! -s "$key_file" ]; then
        if [ -n "${SECRET_KEY:-}" ]; then
            generated_key=$SECRET_KEY
        else
            generated_key=$(openssl rand -hex 32)
        fi
        printf '%s\n' "$generated_key" | atomic_write "$key_file" 0600
        log info "created persistent file download key"
    else
        chmod 0600 "$key_file"
    fi
    chown planet:planet "$key_file"
}

ensure_zerotier_identity() {
    if [ ! -s "$ZEROTIER_PATH/authtoken.secret" ]; then
        openssl rand -hex 24 | atomic_write "$ZEROTIER_PATH/authtoken.secret" 0600
    fi

    if [ ! -s "$ZEROTIER_PATH/identity.secret" ] || [ ! -s "$ZEROTIER_PATH/identity.public" ]; then
        log info "generating ZeroTier identity"
        (
            cd "$ZEROTIER_PATH"
            zerotier-idtool generate identity.secret identity.public
        )
        chmod 0600 "$ZEROTIER_PATH/identity.secret"
        chmod 0644 "$ZEROTIER_PATH/identity.public"
    fi
}

endpoint_json() {
    if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then
        jq -cn --arg ipv4 "$IP_ADDR4/$ZT_PORT" --arg ipv6 "$IP_ADDR6/$ZT_PORT" '[ $ipv4, $ipv6 ]'
    elif [ -n "$IP_ADDR4" ]; then
        jq -cn --arg ipv4 "$IP_ADDR4/$ZT_PORT" '[ $ipv4 ]'
    else
        jq -cn --arg ipv6 "$IP_ADDR6/$ZT_PORT" '[ $ipv6 ]'
    fi
}

generate_worlds() {
    endpoints=$(endpoint_json)
    previous_moon_id=$(jq -r '.id // empty' "$ZEROTIER_PATH/moon.json" 2>/dev/null || true)
    if printf '%s' "$previous_moon_id" | grep -Eq '^[0-9a-f]{16}$'; then
        previous_moon_name=$previous_moon_id.moon
    else
        previous_moon_name=
    fi
    work_dir=$(mktemp -d "$ZEROTIER_PATH/.world.XXXXXX")
    cleanup_world_dir() {
        rm -rf "$work_dir"
    }
    trap cleanup_world_dir EXIT HUP INT TERM

    log info "generating Moon and Planet with official zerotier-idtool"
    zerotier-idtool initmoon "$ZEROTIER_PATH/identity.public" >"$work_dir/moon.json"
    jq --argjson endpoints "$endpoints" '.roots[0].stableEndpoints = $endpoints' \
        "$work_dir/moon.json" >"$work_dir/moon.configured.json"
    jq '.worldType = "planet" | .id = "0000000008eac90a"' \
        "$work_dir/moon.configured.json" >"$work_dir/planet.json"

    (
        cd "$work_dir"
        zerotier-idtool genmoon moon.configured.json
        moon_file=$(find . -maxdepth 1 -type f -name '*.moon' ! -name '0000000008eac90a.moon' -print -quit)
        [ -n "$moon_file" ] || die "zerotier-idtool did not produce a Moon file"
        mv "$moon_file" moon.generated
        zerotier-idtool genmoon planet.json
        [ -s 0000000008eac90a.moon ] || die "zerotier-idtool did not produce the Earth Planet file"
    )

    moon_name=$(jq -r '.id' "$work_dir/moon.configured.json")
    moon_name=$(printf '%016s' "$moon_name" | tr ' ' '0').moon

    cp "$work_dir/moon.configured.json" "$ZEROTIER_PATH/moon.json.tmp"
    cp "$work_dir/planet.json" "$ZEROTIER_PATH/planet.json.tmp"
    cp "$work_dir/moon.generated" "$DIST_PATH/$moon_name.tmp"
    cp "$work_dir/0000000008eac90a.moon" "$DIST_PATH/planet.tmp"
    chmod 0600 "$ZEROTIER_PATH/moon.json.tmp" "$ZEROTIER_PATH/planet.json.tmp"
    chmod 0644 "$DIST_PATH/$moon_name.tmp" "$DIST_PATH/planet.tmp"
    mv -f "$ZEROTIER_PATH/moon.json.tmp" "$ZEROTIER_PATH/moon.json"
    mv -f "$ZEROTIER_PATH/planet.json.tmp" "$ZEROTIER_PATH/planet.json"
    mv -f "$DIST_PATH/$moon_name.tmp" "$DIST_PATH/$moon_name"
    mv -f "$DIST_PATH/planet.tmp" "$DIST_PATH/planet"
    if [ -n "$previous_moon_name" ] && [ "$previous_moon_name" != "$moon_name" ]; then
        rm -f "$DIST_PATH/$previous_moon_name"
    fi

    trap - EXIT HUP INT TERM
    cleanup_world_dir
    log info "generated Planet and Moon artifacts"
}

ensure_worlds() {
    if [ "${PLANET_REGENERATE:-0}" = "1" ] || [ ! -s "$DIST_PATH/planet" ] || ! find "$DIST_PATH" -maxdepth 1 -type f -name '*.moon' | grep -q .; then
        generate_worlds
    else
        log info "existing Planet and Moon artifacts found"
    fi
}

migrate_ztncui_state() {
    state_etc="$ZTNCUI_STATE_PATH/etc"
    if [ ! -d "$state_etc" ]; then
        mkdir -p "$state_etc"
        if [ -d /app/ztncui/src/etc ]; then
            log info "migrating legacy ztncui state"
            cp -a /app/ztncui/src/etc/. "$state_etc/"
        else
            cp -a /opt/ztncui/etc.defaults/. "$state_etc/"
        fi
    fi
    chown planet:planet /app/ztncui
    chown -R planet:planet "$ZTNCUI_STATE_PATH"
}

ensure_ztncui_admin() {
    password_file="$ZTNCUI_STATE_PATH/etc/passwd"
    if [ ! -s "$password_file" ]; then
        if [ -n "${ZTNCUI_ADMIN_PASSWORD:-}" ]; then
            admin_password=$ZTNCUI_ADMIN_PASSWORD
        else
            admin_password=$(openssl rand -base64 24 | tr -d '\r\n')
            printf '%s\n' "$admin_password" | atomic_write "$CONFIG_PATH/ztncui.initial-password" 0600
            chown planet:planet "$CONFIG_PATH/ztncui.initial-password"
        fi
        printf '%s' "$admin_password" | node /opt/planet/container/create-admin.js "$password_file"
        unset admin_password
        log info "created ztncui administrator credentials"
    fi
    chown planet:planet "$password_file"
    chmod 0600 "$password_file"
}

initialize_runtime() {
    require_command curl
    require_command jq
    require_command node
    require_command openssl
    require_command zerotier-idtool

    ensure_file_server_key
    ensure_zerotier_identity
    ensure_worlds
    persist_config
    migrate_ztncui_state
    ensure_ztncui_admin

    export ZT_ADDR="127.0.0.1:$ZT_PORT"
    export ZT_TOKEN
    ZT_TOKEN=$(read_first_line "$ZEROTIER_PATH/authtoken.secret")
    export HTTP_PORT="$API_PORT"
    export NODE_ENV=production
    export HTTP_ALL_INTERFACES=true

    chown -R planet:planet "$CONFIG_PATH" "$DIST_PATH"
}
