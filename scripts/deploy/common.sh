#!/usr/bin/env bash

set -Eeuo pipefail

ENV_FILE=${ENV_FILE:-$PROJECT_ROOT/.env}
COMPOSE_FILE=${COMPOSE_FILE:-$PROJECT_ROOT/compose.yaml}

log() {
    local level=$1
    shift
    printf '%s component=deploy level=%s message=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*"
}

die() {
    log error "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

compose() {
    docker compose \
        --project-directory "$PROJECT_ROOT" \
        --env-file "$ENV_FILE" \
        --file "$COMPOSE_FILE" \
        "$@"
}

container_id() {
    compose ps --all --quiet planet | head -n 1
}

wait_until_healthy() {
    local timeout=${1:-180}
    local started status id
    started=$SECONDS
    while ((SECONDS - started < timeout)); do
        id=$(container_id)
        if [[ -n "$id" ]]; then
            status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)
            case "$status" in
                healthy | running)
                    log info "容器已就绪"
                    return 0
                    ;;
                unhealthy | exited | dead)
                    compose logs --tail 100 planet >&2 || true
                    return 1
                    ;;
            esac
        fi
        sleep 3
    done
    compose logs --tail 100 planet >&2 || true
    return 1
}

safe_data_path() {
    local configured resolved
    configured=$(env_value DATA_DIR './data/zerotier')
    if [[ "$configured" = /* ]]; then
        resolved=$(realpath -m -- "$configured")
    else
        resolved=$(realpath -m -- "$PROJECT_ROOT/$configured")
    fi
    case "$resolved" in
        / | /bin | /boot | /dev | /etc | /home | /lib | /lib64 | /media | /mnt | /opt | /proc | /root | /run | /srv | /sys | /tmp | /usr | /var)
            die "拒绝使用不安全的数据目录：$resolved"
            ;;
    esac
    if [[ "$PROJECT_ROOT/" == "$resolved/"* ]]; then
        die "数据目录不能是项目目录的上级路径：$resolved"
    fi
    printf '%s' "$resolved"
}

create_backup() {
    local data_path backup_root backup_file image id temporary timestamp
    data_path=$(safe_data_path)
    [[ -d "$data_path" ]] || return 0
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    backup_root="$(dirname -- "$data_path")/.zerotier-planet-backups"
    backup_file="$backup_root/zerotier-planet-$timestamp.tar.gz"
    temporary="$backup_file.tmp.$$"
    mkdir -p -- "$backup_root"
    id=$(container_id)
    if [[ -n "$id" ]]; then
        image=$(docker inspect --format '{{.Image}}' "$id")
    else
        image=$(compose config --images | head -n 1)
    fi
    if ! docker run --rm \
        --volume "$data_path:/source:ro" \
        --entrypoint tar \
        "$image" -C /source -czf - . >"$temporary"; then
        rm -f -- "$temporary"
        log error '备份失败'
        return 1
    fi
    chmod 0600 "$temporary"
    mv -f -- "$temporary" "$backup_file"
    log info "备份已创建：$backup_file"
}

usage() {
    cat <<'EOF'
用法：./deploy.sh <command>

命令：
  install          创建配置并启动服务
  status           查看容器、端口和文件位置
  upgrade          备份数据、拉取镜像并升级
  reconfigure      按 .env 重新生成 Planet/Moon
  reset-password   生成或设置新的 ztncui 管理密码
  doctor           执行只读环境诊断
  logs             跟踪容器日志
  stop             停止服务
  uninstall        删除容器但保留数据
  purge --yes-i-understand
                   停止服务并把数据移入可恢复隔离目录
EOF
}
