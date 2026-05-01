#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

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

doctor() {
  [[ -f "$ENV_FILE" ]] || { echo ".env missing; copy .env.example first" >&2; exit 1; }
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
  reset-password   Reset ztncui admin password; pass a password as argv or omit to generate one
  doctor           Validate local config and Compose syntax
EOF
}

main() {
  local command=${1:-}
  shift || true
  case "$command" in
    reset-password) reset_password "$@" ;;
    doctor) doctor "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "unknown command: $command" >&2; usage; exit 1 ;;
  esac
}

main "$@"
