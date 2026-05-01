#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
ENV_EXAMPLE="${ROOT_DIR}/.env.example"
DATA_DIR="${ROOT_DIR}/data/zerotier"
CONFIG_DIR="${DATA_DIR}/config"
DIST_DIR="${DATA_DIR}/dist"

print_message() {
  local message=$1
  local color=${2:-0}
  printf '\033[%sm%s\033[0m\n' "$color" "$message"
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose --project-directory "$ROOT_DIR" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --project-directory "$ROOT_DIR" "$@"
  else
    echo "docker compose is required" >&2
    exit 1
  fi
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
  fi
  CONTAINER_NAME="${CONTAINER_NAME:-myztplanet}"
  API_PORT="${API_PORT:-3443}"
  FILE_SERVER_PORT="${FILE_SERVER_PORT:-3000}"
  ZT_PORT="${ZT_PORT:-9994}"
  HOST_BIND_IP="${HOST_BIND_IP:-127.0.0.1}"
}

public_http_enabled() {
  [[ "${PUBLIC_HTTP:-false}" =~ ^([Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]|[Yy])$ ]]
}

warn_public_http() {
  if public_http_enabled; then
    print_message "警告：PUBLIC_HTTP=true 已启用，管理界面和文件服务将暴露到 HOST_BIND_IP=${HOST_BIND_IP:-0.0.0.0}。" "31"
  fi
}

validate_port() {
  local port=$1
  local name=${2:-port}
  if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
    echo "${name} 必须是 1-65535 之间的数字" >&2
    exit 1
  fi
}

validate_ipv4() {
  local value=$1
  local name=$2
  local IFS=.
  local parts
  read -r -a parts <<< "$value"
  if [[ ${#parts[@]} -ne 4 ]]; then
    echo "${name} 格式不合法" >&2
    exit 1
  fi
  for part in "${parts[@]}"; do
    if [[ ! "$part" =~ ^[0-9]+$ ]] || ((part < 0 || part > 255)); then
      echo "${name} 格式不合法" >&2
      exit 1
    fi
  done
}

validate_ip_value() {
  local value=$1
  local name=$2
  local version=$3
  if [[ -z "$value" ]]; then
    return 0
  fi
  if [[ "$value" =~ [[:space:]\"\'\`] ]] || [[ "$value" == -* ]]; then
    echo "${name} 包含非法字符" >&2
    exit 1
  fi
  if [[ "$version" = "4" ]]; then
    validate_ipv4 "$value" "$name"
  elif [[ ! "$value" =~ ^[0-9A-Fa-f:.]+$ ]] || [[ "$value" != *:* ]]; then
    echo "${name} 格式不合法" >&2
    exit 1
  fi
}

validate_env() {
  validate_port "${ZT_PORT}" "ZeroTier 端口"
  validate_port "${API_PORT}" "API 端口"
  validate_port "${FILE_SERVER_PORT}" "FILE 端口"
  validate_ip_value "${IP_ADDR4:-}" "IPv4 地址" "4"
  validate_ip_value "${IP_ADDR6:-}" "IPv6 地址" "6"
}

ensure_env() {
  if [[ -f "$ENV_FILE" ]]; then
    return 0
  fi
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  print_message "已创建 .env，请按需编辑 IP_ADDR4/IP_ADDR6 和端口后重新运行安装。" "33"
}

read_initial_password_help() {
  echo "ztncui 用户名：admin"
  echo "初始密码读取命令：docker exec ${CONTAINER_NAME} sh -c 'cat /app/config/ztncui.initial-password'"
  echo "登录后请立即修改管理员密码。"
}

download_help() {
  local moon_name
  moon_name="$(find "$DIST_DIR" -maxdepth 1 -type f -name '*.moon' -exec basename {} \; 2>/dev/null | head -n 1 || true)"
  echo "planet 和 moon 文件目录：${DIST_DIR}"
  echo "FILE_KEY=\$(cat ${CONFIG_DIR}/file_server.key)"
  echo "curl -H \"Authorization: Bearer \${FILE_KEY}\" -o planet http://${HOST_BIND_IP}:${FILE_SERVER_PORT}/planet"
  if [[ -n "$moon_name" ]]; then
    echo "curl -H \"Authorization: Bearer \${FILE_KEY}\" -o ${moon_name} http://${HOST_BIND_IP}:${FILE_SERVER_PORT}/${moon_name}"
  fi
}

install() {
  ensure_env
  load_env
  validate_env
  warn_public_http
  compose up -d
  info
}

upgrade() {
  load_env
  compose pull
  compose up -d
}

info() {
  load_env
  if [[ -f "${CONFIG_DIR}/ztncui.port" ]]; then
    API_PORT="$(tr -d '\r' < "${CONFIG_DIR}/ztncui.port")"
  fi
  if [[ -f "${CONFIG_DIR}/file_server.port" ]]; then
    FILE_SERVER_PORT="$(tr -d '\r' < "${CONFIG_DIR}/file_server.port")"
  fi
  echo "管理界面：http://${HOST_BIND_IP}:${API_PORT}"
  read_initial_password_help
  download_help
}

reset_password() {
  load_env
  local password=${1:-}
  local tmp_file
  if [[ -n "$password" ]]; then
    tmp_file="$(mktemp)"
    trap 'rm -f "$tmp_file"' RETURN
    printf '%s\n' "$password" > "$tmp_file"
    docker cp "$tmp_file" "${CONTAINER_NAME}:/tmp/ztncui-reset-password"
    docker exec "$CONTAINER_NAME" sh -c 'ZTNCUI_ADMIN_PASSWORD_FILE=/tmp/ztncui-reset-password node /app/ztncui_admin.js && rm -f /tmp/ztncui-reset-password /app/config/ztncui.initial-password'
  else
    docker exec "$CONTAINER_NAME" sh -c 'umask 077; openssl rand -base64 24 | tr -d "\n" > /app/config/ztncui.initial-password; printf "\n" >> /app/config/ztncui.initial-password; ZTNCUI_ADMIN_PASSWORD_FILE=/app/config/ztncui.initial-password node /app/ztncui_admin.js'
  fi
  docker restart "$CONTAINER_NAME" >/dev/null
  echo "密码已重置。"
  if [[ -z "$password" ]]; then
    echo "读取新密码：docker exec ${CONTAINER_NAME} sh -c 'cat /app/config/ztncui.initial-password'"
  fi
}

uninstall() {
  load_env
  compose down
  read -r -p "是否删除 data/zerotier 数据？(y/n) " delete_data
  if [[ "$delete_data" =~ ^[Yy]$ ]]; then
    rm -rf -- "$DATA_DIR"
  fi
}

doctor() {
  load_env
  validate_env
  compose config >/dev/null
  for required in compose.yaml .env.example patch/entrypoint.sh patch/ztncui_admin.js; do
    [[ -f "${ROOT_DIR}/${required}" ]] || { echo "missing ${required}" >&2; exit 1; }
  done
  echo "doctor checks passed"
}

usage() {
  cat <<'EOF'
Usage: scripts/ztplanet.sh <command>

Commands:
  install          Create .env if needed and start with Docker Compose
  upgrade          Pull image and recreate the Compose service
  info             Show management URL, password and download commands
  reset-password   Reset ztncui admin password; pass a password as argv or omit to generate one
  uninstall        Stop services and optionally remove data
  doctor           Validate local config and Compose syntax
EOF
}

main() {
  local command=${1:-}
  shift || true
  case "$command" in
    install) install "$@" ;;
    upgrade) upgrade "$@" ;;
    info) info "$@" ;;
    reset-password) reset_password "$@" ;;
    uninstall) uninstall "$@" ;;
    doctor) doctor "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "unknown command: $command" >&2; usage; exit 1 ;;
  esac
}

main "$@"
