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
    local ipv4 api_port file_port data_path
    ipv4=$(env_value IP_ADDR4 '<服务器IP>')
    api_port=$(env_value API_PORT 3443)
    file_port=$(env_value FILE_SERVER_PORT 3000)
    data_path=$(safe_data_path)
    printf '管理界面：http://%s:%s\n' "${ipv4:-<服务器IP>}" "$api_port"
    printf 'Planet/Moon：%s/dist\n' "$data_path"
    printf '文件服务端口：%s（密钥保存在 %s/config/file_server.key）\n' "$file_port" "$data_path"
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
