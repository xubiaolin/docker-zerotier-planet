#!/usr/bin/env bats

@test "deploy CLI exposes non-interactive subcommands" {
    run ./deploy.sh help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"reconfigure"* ]]
    [[ "$output" == *"purge --yes-i-understand"* ]]
}

@test "data safety guard rejects filesystem and project ancestors" {
    local env_file project_root
    env_file=$(mktemp)
    project_root="$BATS_TEST_TMPDIR/project/repository"
    mkdir -p "$project_root"
    printf 'DATA_DIR=/\n' >"$env_file"
    run env ENV_FILE="$env_file" PROJECT_ROOT="$project_root" bash -c \
        'source scripts/deploy/config.sh; source scripts/deploy/common.sh; safe_data_path'
    [ "$status" -ne 0 ]
    [[ "$output" == *"不安全的数据目录"* ]]

    printf 'DATA_DIR=%s\n' "$(dirname "$project_root")" >"$env_file"
    run env ENV_FILE="$env_file" PROJECT_ROOT="$project_root" bash -c \
        'source scripts/deploy/config.sh; source scripts/deploy/common.sh; safe_data_path'
    [ "$status" -ne 0 ]
    [[ "$output" == *"上级路径"* ]]
    rm -f "$env_file"
}

@test "status shows persisted addresses and authenticated download URLs" {
    local data_root env_file
    data_root="$BATS_TEST_TMPDIR/runtime"
    env_file="$BATS_TEST_TMPDIR/status.env"
    mkdir -p "$data_root/config" "$data_root/dist"
    printf '%s\n' \
        "DATA_DIR=$data_root" \
        'ZT_PORT=9994' \
        'API_PORT=3443' \
        'FILE_SERVER_PORT=3000' \
        'IP_ADDR4=' \
        'IP_ADDR6=' >"$env_file"
    printf '203.0.113.10\n' >"$data_root/config/ip_addr4"
    printf '2001:db8::10\n' >"$data_root/config/ip_addr6"
    printf '19994\n' >"$data_root/config/zerotier-one.port"
    printf '13443\n' >"$data_root/config/ztncui.port"
    printf '13000\n' >"$data_root/config/file_server.port"
    printf 'secret value&?\n' >"$data_root/config/file_server.key"
    touch "$data_root/dist/planet" "$data_root/dist/0123456789abcdef.moon"

    run env ENV_FILE="$env_file" PROJECT_ROOT="$PWD" bash -c '
        source scripts/deploy/config.sh
        source scripts/deploy/common.sh
        source scripts/deploy/commands.sh
        preflight() { :; }
        ensure_env_file() { :; }
        compose() {
            [[ ${1:-} == ps ]] && printf "planet running (healthy)\n"
        }
        command_status
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"公网 IPv4：203.0.113.10"* ]]
    [[ "$output" == *"IPv4：http://203.0.113.10:13443"* ]]
    [[ "$output" == *"IPv6：http://[2001:db8::10]:13443"* ]]
    [[ "$output" == *"Planet IPv4：http://203.0.113.10:13000/planet?key=secret%20value%26%3F"* ]]
    [[ "$output" == *"Moon IPv6：http://[2001:db8::10]:13000/0123456789abcdef.moon?key=secret%20value%26%3F"* ]]
    [[ "$output" == *"用户名：admin"* ]]
    [[ "$output" != *"<服务器IP>"* ]]
    [[ "$output" != *"首次登录密码"* ]]
}

@test "status explains when no public address is available" {
    local data_root env_file
    data_root="$BATS_TEST_TMPDIR/empty-runtime"
    env_file="$BATS_TEST_TMPDIR/empty-status.env"
    mkdir -p "$data_root"
    printf '%s\n' \
        "DATA_DIR=$data_root" \
        'IP_ADDR4=' \
        'IP_ADDR6=' >"$env_file"

    run env ENV_FILE="$env_file" PROJECT_ROOT="$PWD" bash -c '
        source scripts/deploy/config.sh
        source scripts/deploy/common.sh
        source scripts/deploy/commands.sh
        preflight() { :; }
        ensure_env_file() { :; }
        compose() {
            if [[ ${1:-} == ps ]]; then
                printf "planet stopped\n"
                return 0
            fi
            return 1
        }
        command_status
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"公网地址：尚未探测到有效地址"* ]]
    [[ "$output" == *"无法生成管理地址：缺少有效公网 IP"* ]]
    [[ "$output" == *"无法生成下载 URL：缺少有效公网 IP"* ]]
    [[ "$output" != *"http://"* ]]
}

@test "initial administrator password is displayed and consumed once" {
    local password_file
    password_file="$BATS_TEST_TMPDIR/initial-password"
    printf 'a-unique-initial-password\n' >"$password_file"

    run env PASSWORD_FILE="$password_file" bash -c '
        source scripts/deploy/commands.sh
        compose() {
            if [[ ${4:-} == test ]]; then
                test -s "$PASSWORD_FILE"
            elif [[ ${4:-} == sh ]]; then
                cat "$PASSWORD_FILE"
                rm -f "$PASSWORD_FILE"
            else
                return 1
            fi
        }
        show_initial_password
        show_initial_password
    '

    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '首次登录密码')" -eq 1 ]
    [[ "$output" == *"a-unique-initial-password"* ]]
    [ ! -e "$password_file" ]
}
