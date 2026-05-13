#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_entrypoint_functions() {
  source <(sed '/^check_file_server$/,$d' "$REPO_ROOT/patch/entrypoint.sh")
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_file_contains() {
  local pattern="$1"
  local file="$2"

  grep -Eq "$pattern" "$file" || {
    echo "missing pattern '$pattern' in $file" >&2
    exit 1
  }
}

assert_file_exists() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo "missing expected file: $file" >&2
    exit 1
  fi
}

test_existing_zerotier_data_rejects_port_change() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  ZEROTIER_PATH="$tmp/zerotier-one"
  CONFIG_PATH="$tmp/config"
  mkdir -p "$ZEROTIER_PATH" "$CONFIG_PATH"
  printf '%s\n' "existing data" > "$ZEROTIER_PATH/identity.public"
  printf '%s\n' "9994" > "$CONFIG_PATH/zerotier-one.port"

  set +e
  (
    load_entrypoint_functions
    ZEROTIER_PATH="$tmp/zerotier-one"
    CONFIG_PATH="$tmp/config"
    ZT_PORT="12345"
    check_zerotier
  ) > "$tmp/output" 2>&1
  local status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "existing ZeroTier data should reject a changed ZT_PORT" >&2
    exit 1
  fi
  assert_file_contains 'ZT_PORT changed from 9994 to 12345' "$tmp/output"
  assert_equals "9994" "$(cat "$CONFIG_PATH/zerotier-one.port")" "existing ZeroTier port should remain unchanged after rejected change"
}

test_existing_zerotier_data_requires_saved_port() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  ZEROTIER_PATH="$tmp/zerotier-one"
  CONFIG_PATH="$tmp/config"
  mkdir -p "$ZEROTIER_PATH" "$CONFIG_PATH"
  printf '%s\n' "existing data" > "$ZEROTIER_PATH/identity.public"

  set +e
  (
    load_entrypoint_functions
    ZEROTIER_PATH="$tmp/zerotier-one"
    CONFIG_PATH="$tmp/config"
    ZT_PORT="9994"
    check_zerotier
  ) > "$tmp/output" 2>&1
  local status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "existing ZeroTier data should require a saved ZT_PORT" >&2
    exit 1
  fi
  assert_file_contains 'Existing ZeroTier data requires .*/zerotier-one.port' "$tmp/output"
  if [ -e "$CONFIG_PATH/zerotier-one.port" ]; then
    echo "missing saved port should not be recreated for existing ZeroTier data" >&2
    exit 1
  fi
}

test_incomplete_first_run_retries_initialization() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  ZEROTIER_PATH="$tmp/zerotier-one"
  CONFIG_PATH="$tmp/config"
  mkdir -p "$ZEROTIER_PATH" "$CONFIG_PATH"
  printf '%s\n' "9994" > "$CONFIG_PATH/zerotier-one.port"
  printf '%s\n' "initializing" > "$CONFIG_PATH/zerotier-one.init-status"
  printf '%s\n' "partial data" > "$ZEROTIER_PATH/identity.public"

  (
    load_entrypoint_functions
    ZEROTIER_PATH="$tmp/zerotier-one"
    CONFIG_PATH="$tmp/config"
    ZT_PORT="9994"
    init_zerotier_data() {
      if [ -e "$ZEROTIER_PATH/identity.public" ]; then
        echo "partial ZeroTier data was not cleared before retry" >&2
        return 1
      fi
      printf '%s\n' "retried" > "$CONFIG_PATH/retry"
    }
    check_zerotier
  ) > "$tmp/output" 2>&1

  assert_file_contains 'Incomplete ZeroTier initialization detected' "$tmp/output"
  assert_equals "retried" "$(cat "$CONFIG_PATH/retry")" "incomplete first-run state should retry initialization"
}

test_init_zerotier_data_generates_planet_with_idtool() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  load_entrypoint_functions
  APP_PATH="$tmp/app"
  BACKUP_PATH="$tmp/bak"
  ZEROTIER_PATH="$tmp/zerotier-one"
  CONFIG_PATH="$tmp/config"
  IP_ADDR4="203.0.113.10"
  IP_ADDR6=""
  ZT_PORT="9994"
  mkdir -p "$BACKUP_PATH/zerotier-one" "$APP_PATH/dist"
  cat > "$BACKUP_PATH/zerotier-one/zerotier-idtool" <<'IDTOOL'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
  generate)
    printf '%s\n' "secret" > "$2"
    printf '%s\n' "public" > "$3"
    ;;
  initmoon)
    cat <<'JSON'
{
  "objtype": "world",
  "worldType": "moon",
  "updatesMustBeSignedBy": "public-key",
  "signingKey": "public-key",
  "signingKey_SECRET": "secret-key",
  "id": "1234567890",
  "roots": [
    {
      "identity": "root-identity",
      "stableEndpoints": []
    }
  ]
}
JSON
    ;;
  genmoon)
    if grep -q '"worldType": "planet"' "$2"; then
      grep -q '"id": "0000000008eac90a"' "$2"
      printf '%s\n' "planet-world" > 0000000008eac90a.moon
    else
      printf '%s\n' "moon-world" > 1234567890.moon
    fi
    ;;
  *)
    echo "unexpected zerotier-idtool command: $*" >&2
    exit 1
    ;;
esac
IDTOOL
  chmod +x "$BACKUP_PATH/zerotier-one/zerotier-idtool"

  init_zerotier_data > "$tmp/init-output" 2>&1

  assert_file_exists "$APP_PATH/dist/planet"
  assert_file_exists "$APP_PATH/dist/1234567890.moon"
  assert_file_contains '"worldType": "planet"' "$ZEROTIER_PATH/planet.json"
  assert_file_contains '"id": "0000000008eac90a"' "$ZEROTIER_PATH/planet.json"
  assert_equals "planet-world" "$(cat "$APP_PATH/dist/planet")" "planet should be generated by zerotier-idtool genmoon"
  assert_equals "complete" "$(cat "$CONFIG_PATH/zerotier-one.init-status")" "successful initialization should be marked complete"
}

test_file_key_persistence_restores_umask() {
  local tmp
  local saved_umask
  local after_umask

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  load_entrypoint_functions
  CONFIG_PATH="$tmp/config"
  FILE_KEY="test-file-key"

  saved_umask="$(umask)"
  umask 022
  persist_file_key
  after_umask="$(umask)"
  umask "$saved_umask"

  assert_equals "0022" "$after_umask" "persist_file_key should restore the caller umask"
  assert_equals "600" "$(stat -c '%a' "$CONFIG_PATH/file_server.key")" "persisted file key should be owner-only"
  assert_equals "test-file-key" "$(cat "$CONFIG_PATH/file_server.key")" "persisted file key should match FILE_KEY"
}

test_ztncui_env_preserves_custom_settings() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  load_entrypoint_functions
  ZEROTIER_PATH="$tmp/zerotier-one"
  ZTNCUI_SRC_PATH="$tmp/ztncui/src"
  API_PORT="3443"
  ZT_PORT="9994"
  mkdir -p "$ZEROTIER_PATH" "$ZTNCUI_SRC_PATH"
  printf '%s\n' "token-value" > "$ZEROTIER_PATH/authtoken.secret"
  cat > "$ZTNCUI_SRC_PATH/.env" <<'ENV'
HTTPS_PORT=9443
HTTPS_HOST=0.0.0.0
HTTP_PORT=1111
ZT_TOKEN=old-token
ENV

  write_ztncui_env

  assert_file_contains '^HTTPS_PORT=9443$' "$ZTNCUI_SRC_PATH/.env"
  assert_file_contains '^HTTPS_HOST=0\.0\.0\.0$' "$ZTNCUI_SRC_PATH/.env"
  assert_file_contains '^HTTP_PORT=3443$' "$ZTNCUI_SRC_PATH/.env"
  assert_file_contains '^HTTP_ALL_INTERFACES=true$' "$ZTNCUI_SRC_PATH/.env"
  assert_file_contains '^ZT_ADDR=localhost:9994$' "$ZTNCUI_SRC_PATH/.env"
  assert_file_contains '^ZT_TOKEN=token-value$' "$ZTNCUI_SRC_PATH/.env"
}

test_existing_zerotier_data_rejects_port_change
test_existing_zerotier_data_requires_saved_port
test_incomplete_first_run_retries_initialization
test_init_zerotier_data_generates_planet_with_idtool
test_file_key_persistence_restores_umask
test_ztncui_env_preserves_custom_settings

echo "entrypoint config checks passed"
