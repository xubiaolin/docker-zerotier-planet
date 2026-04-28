#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

report_pass() {
  printf 'PASS: %s\n' "$1"
}

report_fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    report_pass "required file exists: $file"
  else
    report_fail "required file missing: $file"
  fi
}

require_match() {
  local name="$1"
  local pattern="$2"
  shift 2
  local output
  if output=$(grep -RInE -- "$pattern" "$@" 2>/dev/null); then
    report_pass "$name"
  else
    report_fail "$name (pattern not found: $pattern in $*)"
  fi
}

require_any_match() {
  local name="$1"
  local file="$2"
  shift 2
  local pattern
  for pattern in "$@"; do
    if grep -Eq -- "$pattern" "$file" 2>/dev/null; then
      report_pass "$name"
      return 0
    fi
  done
  report_fail "$name (none of the accepted patterns were found in $file)"
}

reject_legacy_public_default_bindings() {
  local direct_public='-p[[:space:]]+\$\{?(API_PORT|FILE_PORT)\}?:\$\{?(API_PORT|FILE_PORT)\}?'
  local explicit_opt_in='PUBLIC_HTTP|ZTNCUI_HTTP_PUBLIC|FILE_SERVER_HTTP_PUBLIC|HTTP_PUBLIC'
  local output
  if output=$(grep -nE -- "$direct_public" deploy.sh 2>/dev/null); then
    if grep -Eq -- "$explicit_opt_in" deploy.sh; then
      report_pass 'deploy gates public management/file-server bindings behind an explicit opt-in flag'
    else
      report_fail 'deploy does not publish management/file-server ports on every host interface by default (unexpected direct public bindings):'
      printf '%s
' "$output" >&2
    fi
  else
    report_pass 'deploy does not publish management/file-server ports on every host interface by default'
  fi
}

reject_match() {
  local name="$1"
  local pattern="$2"
  shift 2
  local output
  if output=$(grep -RInE -- "$pattern" "$@" 2>/dev/null); then
    report_fail "$name (unexpected matches):"
    printf '%s\n' "$output" >&2
  else
    report_pass "$name"
  fi
}

tracked_security_files=(
  Dockerfile
  deploy.sh
  patch/entrypoint.sh
  patch/http_server.js
  README.md
  README.en.md
  .github/workflows/image-build.yml
)

docs_and_deploy=(
  deploy.sh
  README.md
  README.en.md
)

for file in "${tracked_security_files[@]}"; do
  require_file "$file"
done
require_file test/http_server_security.test.js

reject_match \
  'docs/deploy do not recommend query-string file-server secrets' \
  '\?key=' \
  "${docs_and_deploy[@]}"

reject_match \
  'deploy/docs do not advertise the historical admin/password credential' \
  '(默认密码[：:][[:space:]]*password|Default password[[:space:]]*:[[:space:]]*password|admin[[:space:]]*/[[:space:]]*password|admin/password)' \
  "${docs_and_deploy[@]}"

reject_match \
  'entrypoint does not restore upstream default passwd' \
  'cp[[:space:]-]+(-v[[:space:]]+)?etc/default\.passwd[[:space:]]+etc/passwd' \
  patch/entrypoint.sh

reject_match \
  'entrypoint does not run with global shell xtrace' \
  '^[[:space:]]*set[[:space:]]+-x' \
  patch/entrypoint.sh

reject_match \
  'entrypoint does not force ztncui HTTP on all interfaces' \
  'HTTP_ALL_INTERFACES=true' \
  patch/entrypoint.sh

reject_match \
  'deploy output does not print raw file-server key variables' \
  '(KEY:[[:space:]]*\$\{?KEY\}?|echo[[:space:]].*(KEY|key).*\$\{?KEY\}?|print_message[[:space:]].*\$\{?KEY\}?)' \
  deploy.sh

reject_legacy_public_default_bindings

require_match \
  'deploy default host binding helper returns localhost' \
  '127\.0\.0\.1' \
  deploy.sh

require_any_match \
  'deploy binds management port to localhost by default' \
  deploy.sh \
  '127\.0\.0\.1:\$\{?API_PORT\}?:\$\{?API_PORT\}?' \
  '-p[[:space:]]+\$\{?[A-Z_]*(BIND|HOST)[A-Z_]*\}?:\$\{?API_PORT\}?:\$\{?API_PORT\}?'

require_any_match \
  'deploy binds file-server port to localhost by default' \
  deploy.sh \
  '127\.0\.0\.1:\$\{?FILE_PORT\}?:\$\{?FILE_PORT\}?' \
  '-p[[:space:]]+\$\{?[A-Z_]*(BIND|HOST)[A-Z_]*\}?:\$\{?FILE_PORT\}?:\$\{?FILE_PORT\}?'

require_match \
  'Dockerfile declares a pinned ztncui ref build arg' \
  'ARG[[:space:]]+ZTNCUI_REF=' \
  Dockerfile

require_match \
  'Dockerfile checks out the pinned ztncui ref' \
  'git[[:space:]]+checkout[[:space:]]+--detach[[:space:]]+"?\$\{?ZTNCUI_REF\}?"?' \
  Dockerfile

require_match \
  'Dockerfile verifies ztncui full-SHA checkout with git rev-parse' \
  'git[[:space:]]+rev-parse[[:space:]]+HEAD' \
  Dockerfile

require_match \
  'GitHub workflow passes explicit ZTNCUI_REF build arg' \
  'ZTNCUI_REF=' \
  .github/workflows/image-build.yml

require_match \
  'file server supports Authorization bearer header auth' \
  'Authorization|authorization' \
  patch/http_server.js

require_match \
  'file server uses constant-time secret comparison' \
  'timingSafeEqual' \
  patch/http_server.js

require_match \
  'file server gates query-string compatibility behind explicit opt-in' \
  'ALLOW_QUERY_FILE_KEY' \
  patch/http_server.js

require_match \
  'file server writes secret file with 0600 permissions' \
  '0o600' \
  patch/http_server.js

require_match \
  'file server generates at least a 256-bit random key' \
  'randomBytes\((KEY_BYTES|32)\)' \
  patch/http_server.js

require_match \
  'file server allows only planet and .moon artifacts' \
  'planet.*\.moon|\.moon.*planet|isAllowedArtifact' \
  patch/http_server.js

if (( failures > 0 )); then
  printf '\nStatic security checks failed: %d issue(s).\n' "$failures" >&2
  exit 1
fi

printf '\nStatic security checks passed.\n'
