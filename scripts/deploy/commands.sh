#!/usr/bin/env bash

set -Eeuo pipefail

preflight() {
    require_command docker
    require_command realpath
    docker info >/dev/null 2>&1 || die 'Docker daemon 不可用'
    docker compose version >/dev/null 2>&1 || die 'Docker Compose 插件不可用'
}

show_initial_password() {
    local password
    if compose exec -T planet test -s /app/config/ztncui.initial-password >/dev/null 2>&1; then
        password=$(compose exec -T planet sh -c 'cat /app/config/ztncui.initial-password && rm -f /app/config/ztncui.initial-password')
        printf '\n首次登录用户名：admin\n首次登录密码：%s\n请立即登录并修改密码；该密码不会再次显示。\n\n' "$password"
    fi
}

read_runtime_file() {
    local relative_path=$1
    local data_path value=
    data_path=$(safe_data_path)

    if [[ -r "$data_path/$relative_path" ]]; then
        IFS= read -r value <"$data_path/$relative_path" || true
        printf '%s' "${value%$'\r'}"
        return 0
    fi

    if value=$(compose exec -T planet cat "/app/$relative_path" 2>/dev/null); then
        printf '%s' "${value%$'\r'}"
        return 0
    fi

    return 1
}

runtime_config_value() {
    local environment_key=$1
    local config_file=$2
    local fallback=$3
    local value

    if value=$(read_runtime_file "config/$config_file"); then
        printf '%s' "$value"
    else
        env_value "$environment_key" "$fallback"
    fi
}

list_runtime_artifacts() {
    local data_path output path name
    data_path=$(safe_data_path)

    if [[ -d "$data_path/dist" && -r "$data_path/dist" && -x "$data_path/dist" ]]; then
        if [[ -f "$data_path/dist/planet" && ! -L "$data_path/dist/planet" ]]; then
            printf 'planet\n'
        fi
        for path in "$data_path"/dist/*.moon; do
            [[ -f "$path" && ! -L "$path" ]] || continue
            name=${path##*/}
            if [[ "$name" =~ ^[0-9a-f]{16}\.moon$ ]]; then
                printf '%s\n' "$name"
            fi
        done | LC_ALL=C sort -u
        return 0
    fi

    if output=$(compose exec -T planet find /app/dist -maxdepth 1 -type f -printf '%f\n' 2>/dev/null); then
        while IFS= read -r name; do
            if [[ "$name" == planet ]]; then
                printf 'planet\n'
                break
            fi
        done <<<"$output"
        while IFS= read -r name; do
            if [[ "$name" =~ ^[0-9a-f]{16}\.moon$ ]]; then
                printf '%s\n' "$name"
            fi
        done <<<"$output" | LC_ALL=C sort -u
        return 0
    fi

    return 1
}

percent_encode() {
    local value=$1
    local encoded='' character hex i
    local LC_ALL=C

    for ((i = 0; i < ${#value}; i++)); do
        character=${value:i:1}
        case "$character" in
            [a-zA-Z0-9.~_-]) encoded+=$character ;;
            *)
                printf -v hex '%%%02X' "'$character"
                encoded+=$hex
                ;;
        esac
    done

    printf '%s' "$encoded"
}

url_host() {
    local address=$1
    if [[ "$address" == *:* ]]; then
        printf '[%s]' "$address"
    else
        printf '%s' "$address"
    fi
}

print_http_url() {
    local label=$1
    local address=$2
    local port=$3
    local path=${4:-}
    local query=${5:-}
    local host
    host=$(url_host "$address")
    printf '  %s：http://%s:%s%s%s\n' "$label" "$host" "$port" "$path" "$query"
}

command_install() {
    preflight
    ensure_env_file prompt
    compose config --quiet
    mkdir -p -- "$(safe_data_path)"
    compose up --detach --remove-orphans planet
    wait_until_healthy 240 || die '服务未能通过健康检查'
    show_initial_password
    command_status
}

command_status() {
    preflight
    ensure_env_file
    compose ps
    local api_port artifacts data_path download_key encoded_key file_port ipv4 ipv6 zt_port
    local artifact artifact_label
    ipv4=$(runtime_config_value IP_ADDR4 ip_addr4 '')
    ipv6=$(runtime_config_value IP_ADDR6 ip_addr6 '')
    zt_port=$(runtime_config_value ZT_PORT zerotier-one.port 9994)
    api_port=$(runtime_config_value API_PORT ztncui.port 3443)
    file_port=$(runtime_config_value FILE_SERVER_PORT file_server.port 3000)
    data_path=$(safe_data_path)

    printf '\n部署信息：\n'
    if [[ -n "$ipv4" ]]; then
        printf '  公网 IPv4：%s\n' "$ipv4"
    fi
    if [[ -n "$ipv6" ]]; then
        printf '  公网 IPv6：%s\n' "$ipv6"
    fi
    if [[ -z "$ipv4" && -z "$ipv6" ]]; then
        printf '  公网地址：尚未探测到有效地址\n'
    fi

    printf '\nPlanet 节点：\n'
    if [[ -n "$ipv4" ]]; then
        printf '  IPv4：%s/%s（TCP/UDP）\n' "$ipv4" "$zt_port"
    fi
    if [[ -n "$ipv6" ]]; then
        printf '  IPv6：%s/%s（TCP/UDP）\n' "$ipv6" "$zt_port"
    fi
    if [[ -z "$ipv4" && -z "$ipv6" ]]; then
        printf '  无法生成节点地址：缺少有效公网 IP\n'
    fi

    printf '\n管理后台：\n'
    if [[ -n "$ipv4" ]]; then
        print_http_url 'IPv4' "$ipv4" "$api_port"
    fi
    if [[ -n "$ipv6" ]]; then
        print_http_url 'IPv6' "$ipv6" "$api_port"
    fi
    if [[ -z "$ipv4" && -z "$ipv6" ]]; then
        printf '  无法生成管理地址：缺少有效公网 IP\n'
    fi
    printf '  用户名：admin\n'

    printf '\nPlanet/Moon 下载（以下 URL 包含访问密钥，请勿公开）：\n'
    if [[ -z "$ipv4" && -z "$ipv6" ]]; then
        printf '  无法生成下载 URL：缺少有效公网 IP\n'
    elif ! download_key=$(read_runtime_file config/file_server.key) || [[ -z "$download_key" ]]; then
        printf '  无法读取下载密钥；请确认容器正在运行后重试\n'
    elif ! artifacts=$(list_runtime_artifacts) || [[ -z "$artifacts" ]]; then
        printf '  尚未找到 Planet/Moon 文件\n'
    else
        encoded_key=$(percent_encode "$download_key")
        while IFS= read -r artifact; do
            [[ -n "$artifact" ]] || continue
            if [[ "$artifact" == planet ]]; then
                artifact_label=Planet
            else
                artifact_label=Moon
            fi
            if [[ -n "$ipv4" ]]; then
                print_http_url "$artifact_label IPv4" "$ipv4" "$file_port" "/$artifact" "?key=$encoded_key"
            fi
            if [[ -n "$ipv6" ]]; then
                print_http_url "$artifact_label IPv6" "$ipv6" "$file_port" "/$artifact" "?key=$encoded_key"
            fi
        done <<<"$artifacts"
    fi

    printf '\n本地文件：\n'
    printf '  Planet/Moon：%s/dist\n' "$data_path"
    printf '  下载密钥：%s/config/file_server.key\n' "$data_path"
}

command_upgrade() {
    preflight
    ensure_env_file
    local id old_image image rollback_tag timestamp
    id=$(container_id)
    [[ -n "$id" ]] || die '容器不存在，请先运行 install'
    old_image=$(docker inspect --format '{{.Image}}' "$id")
    image=$(compose config --images | head -n 1)
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    rollback_tag="zerotier-planet-rollback:$timestamp"
    docker image tag "$old_image" "$rollback_tag"
    compose pull planet
    compose stop planet
    if ! create_backup; then
        compose start planet || true
        die '升级前备份失败，旧容器已重新启动'
    fi
    compose up --detach --remove-orphans planet
    if ! wait_until_healthy 240; then
        log error '新镜像健康检查失败，正在恢复旧镜像'
        docker image tag "$rollback_tag" "$image"
        compose up --detach --force-recreate planet
        wait_until_healthy 180 || die "自动恢复失败；旧镜像保留为 $rollback_tag"
        die "升级失败，已恢复旧镜像；保留标签：$rollback_tag"
    fi
    log info "升级完成；回滚镜像保留为 $rollback_tag"
}

command_reconfigure() {
    preflight
    ensure_env_file prompt
    compose stop planet || true
    if ! create_backup; then
        compose start planet || true
        die '重新配置前备份失败，原服务已重新启动'
    fi
    if ! compose run --rm --no-deps -e PLANET_REGENERATE=1 planet true; then
        compose start planet || true
        die '重新生成失败，备份与原有产物均已保留'
    fi
    compose up --detach planet
    wait_until_healthy 240 || die '重新配置后服务未通过健康检查'
}

command_reset_password() {
    preflight
    ensure_env_file
    require_command openssl
    local password confirmation
    if [[ -t 0 ]]; then
        read -r -s -p '新密码（至少 16 个字符；留空则自动生成）：' password
        printf '\n'
        if [[ -n "$password" ]]; then
            read -r -s -p '再次输入新密码：' confirmation
            printf '\n'
            [[ "$password" == "$confirmation" ]] || die '两次输入的密码不一致'
        fi
    fi
    if [[ -z "${password:-}" ]]; then
        password=$(openssl rand -base64 24 | tr -d '\r\n')
    fi
    ((${#password} >= 16)) || die '密码至少需要 16 个字符'
    printf '%s' "$password" | compose exec -T planet node /opt/planet/container/create-admin.js /app/ztncui/state/etc/passwd
    compose exec -T planet chown planet:planet /app/ztncui/state/etc/passwd
    compose restart planet
    wait_until_healthy 180 || die '密码已更新，但服务重启后未通过健康检查'
    printf '用户名：admin\n新密码：%s\n请安全保存。\n' "$password"
}

command_doctor() {
    local api_port failures=0 file_port port zt_port
    preflight
    ensure_env_file
    compose config --quiet || failures=$((failures + 1))
    zt_port=$(env_value ZT_PORT 9994)
    api_port=$(env_value API_PORT 3443)
    file_port=$(env_value FILE_SERVER_PORT 3000)
    for port in "$zt_port" "$api_port" "$file_port"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
            log error "非法端口：$port"
            failures=$((failures + 1))
        fi
    done
    if [[ "$zt_port" == "$api_port" || "$zt_port" == "$file_port" || "$api_port" == "$file_port" ]]; then
        log error '三个服务端口必须互不相同'
        failures=$((failures + 1))
    fi
    log info "数据目录：$(safe_data_path)"
    if ((failures > 0)); then
        die "诊断发现 $failures 个问题"
    fi
    log info '诊断通过'
}

command_uninstall() {
    preflight
    ensure_env_file
    compose down --remove-orphans
    log info "容器已删除，数据保留在 $(safe_data_path)"
}

command_purge() {
    [[ ${1:-} == --yes-i-understand ]] || die 'purge 必须附带 --yes-i-understand'
    preflight
    ensure_env_file
    local data_path quarantine
    data_path=$(safe_data_path)
    compose down --remove-orphans
    if [[ -e "$data_path" ]]; then
        quarantine="${data_path}.purged.$(date -u +%Y%m%dT%H%M%SZ)"
        mv -- "$data_path" "$quarantine"
        log info "数据已移至可恢复隔离目录：$quarantine"
    fi
}
