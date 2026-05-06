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
  .dockerignore
  compose.yaml
  .env.example
  scripts/install-zerotier-client.sh
  scripts/install-zerotier-client.ps1
  scripts/ztplanet.sh
  patch/entrypoint.sh
  patch/http_server.js
  patch/ztncui_admin.js
  README.md
  README.en.md
  .github/workflows/image-build.yml
)

docs_and_deploy=(
  scripts/ztplanet.sh
  README.md
  README.en.md
)

client_install_scripts=(
  scripts/install-zerotier-client.sh
  scripts/install-zerotier-client.ps1
)

for file in "${tracked_security_files[@]}"; do
  require_file "$file"
done
require_file test/http_server_security.test.js

require_match \
  'client one-click scripts use Authorization bearer header for planet downloads' \
  'Authorization:[[:space:]]*Bearer' \
  "${client_install_scripts[@]}"

reject_match \
  'client one-click scripts do not use query-string file-server secrets' \
  '\?key=' \
  "${client_install_scripts[@]}"

require_match \
  'Unix client installer checks for root privileges' \
  'EUID|id -u' \
  scripts/install-zerotier-client.sh

require_match \
  'Windows client installer checks for administrator privileges' \
  'WindowsPrincipal|Administrator' \
  scripts/install-zerotier-client.ps1

require_match \
  'Unix client installer covers Linux ZeroTier data directory' \
  '/var/lib/zerotier-one/planet' \
  scripts/install-zerotier-client.sh

require_match \
  'Unix client installer covers macOS ZeroTier data directory' \
  '/Library/Application Support/ZeroTier/One/planet' \
  scripts/install-zerotier-client.sh

require_match \
  'Windows client installer covers ZeroTier data directory' \
  'C:\\ProgramData\\ZeroTier\\One\\planet' \
  scripts/install-zerotier-client.ps1

require_match \
  'Windows client installer restarts the ZeroTier service' \
  'ZeroTierOneService' \
  scripts/install-zerotier-client.ps1

require_match \
  'Unix client installer restarts Linux ZeroTier through service managers' \
  'systemctl.*zerotier-one|service.*zerotier-one' \
  scripts/install-zerotier-client.sh

require_match \
  'Unix client installer restarts macOS ZeroTier through the LaunchDaemon' \
  '/Library/LaunchDaemons/com.zerotier.one.plist' \
  scripts/install-zerotier-client.sh

require_match \
  'README documents Compose-first install flow' \
  'docker compose up -d' \
  README.md

require_match \
  'English README documents Compose-first install flow' \
  'docker compose up -d' \
  README.en.md

require_match \
  'README links to the actual English document' \
  'README\.en\.md' \
  README.md

require_match \
  'Chinese README install section uses Docker Compose wording' \
  '### 3\.3 使用 Docker Compose 安装' \
  README.md

require_match \
  'English README install section uses Docker Compose wording' \
  '### 3\.3 Install with Docker Compose' \
  README.en.md

require_match \
  'compose binds management UI to localhost by default' \
  '\$\{HOST_BIND_IP:-127\.0\.0\.1\}:\$\{API_PORT:-3443\}:\$\{API_PORT:-3443\}' \
  compose.yaml

require_match \
  'compose binds file server to localhost by default' \
  '\$\{HOST_BIND_IP:-127\.0\.0\.1\}:\$\{FILE_SERVER_PORT:-3000\}:\$\{FILE_SERVER_PORT:-3000\}' \
  compose.yaml

require_match \
  'env example keeps management and file services local by default' \
  '^HOST_BIND_IP=127\.0\.0\.1$' \
  .env.example

require_match \
  'maintenance helper exposes reset-password command' \
  'reset-password' \
  scripts/ztplanet.sh

require_match \
  'ztncui admin helper hashes credentials with argon2' \
  'argon2\.hash' \
  patch/ztncui_admin.js

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

require_match \
  'maintenance helper exposes doctor command' \
  'doctor' \
  scripts/ztplanet.sh

reject_match \
  'maintenance helper does not expose install wrappers anymore' \
  '(install|upgrade|uninstall|info)' \
  scripts/ztplanet.sh

reject_match \
  'server deployment docs no longer reference deploy.sh' \
  'deploy\.sh' \
  README.md README.en.md SECURITY.md

require_match \
  'README title no longer advertises one-click server deployment' \
  '^>[[:space:]]*(使用 Docker Compose 部署|Deploy a ZeroTier Planet server with Docker Compose)' \
  README.md README.en.md

require_match \
  'maintenance script validates numeric ports from config files' \
  'validate_port' \
  scripts/ztplanet.sh

require_match \
  'maintenance script validates IP address values before compose up' \
  'validate_ip_value' \
  scripts/ztplanet.sh

require_match \
  'compose passes IP_ADDR4 through structured environment' \
  'IP_ADDR4:[[:space:]]+\$\{IP_ADDR4:-\}' \
  compose.yaml

require_match \
  'compose applies no-new-privileges to container runtime' \
  'no-new-privileges:true' \
  compose.yaml

require_match \
  'entrypoint supports documented ztncui bootstrap password env var' \
  'ZTNCUI_BOOTSTRAP_PASSWORD' \
  patch/entrypoint.sh

require_match \
  'entrypoint supports documented ztncui bootstrap password file env var' \
  'ZTNCUI_BOOTSTRAP_PASSWORD_FILE' \
  patch/entrypoint.sh

require_match \
  'entrypoint does not curl IPv6 when IP_ADDR6 is explicitly empty' \
  'IP_ADDR6\+x' \
  patch/entrypoint.sh

require_match \
  'entrypoint tolerates public IP discovery curl failures' \
  'curl[[:space:]].*\|\|[[:space:]]+true' \
  patch/entrypoint.sh

require_any_match \
  'compose binds management port to localhost by default' \
  compose.yaml \
  '127\.0\.0\.1:\$\{?API_PORT\}?:\$\{?API_PORT\}?' \
  '-p[[:space:]]+\$\{?[A-Z_]*(BIND|HOST)[A-Z_]*\}?:\$\{?API_PORT\}?:\$\{?API_PORT\}?' \
  '\$\{?[A-Z_]*(BIND|HOST)[A-Z_]*:-127\.0\.0\.1\}?:\$\{?API_PORT'

require_any_match \
  'compose binds file-server port to localhost by default' \
  compose.yaml \
  '127\.0\.0\.1:\$\{?FILE_PORT\}?:\$\{?FILE_PORT\}?' \
  '-p[[:space:]]+\$\{?[A-Z_]*(BIND|HOST)[A-Z_]*\}?:\$\{?FILE_PORT\}?:\$\{?FILE_PORT\}?' \
  '\$\{?[A-Z_]*(BIND|HOST)[A-Z_]*:-127\.0\.0\.1\}?:\$\{?FILE_SERVER_PORT'

require_match \
  'Dockerfile declares a pinned ztncui ref build arg' \
  'ARG[[:space:]]+ZTNCUI_REF=' \
  Dockerfile

require_match \
  'Dockerfile declares an explicit ZeroTier source ref build arg' \
  'ARG[[:space:]]+ZEROTIER_REF=' \
  Dockerfile

require_match \
  'Dockerfile verifies ZeroTier checkout with git rev-parse' \
  'test[[:space:]]+"\$\(git[[:space:]]+rev-parse[[:space:]]+HEAD\)"[[:space:]]=' \
  Dockerfile

reject_match \
  'Dockerfile uses COPY for local files instead of ADD' \
  '^[[:space:]]*ADD[[:space:]]+' \
  Dockerfile

reject_match \
  'Dockerfile avoids apk update layers when apk add --no-cache is enough' \
  'apk[[:space:]]+update' \
  Dockerfile

require_match \
  'Dockerfile installs runtime dependencies in a named virtual package' \
  '--virtual[[:space:]]+\.runtime-deps' \
  Dockerfile

require_match \
  'Dockerfile removes ztncui git metadata before final image copy' \
  'rm[[:space:]-]+.*\/app\/ztncui\/\.git' \
  Dockerfile

require_match \
  'Dockerfile copies entrypoint in runtime stage to preserve builder cache' \
  'COPY[[:space:]]+\./patch/entrypoint\.sh[[:space:]]+/app/entrypoint\.sh' \
  Dockerfile

require_match \
  'Docker build context ignores git metadata' \
  '^\.git$' \
  .dockerignore

require_match \
  'Docker build context ignores runtime data directory' \
  '^data$' \
  .dockerignore

require_match \
  'Dockerfile checks out the pinned ztncui ref' \
  'git[[:space:]]+checkout[[:space:]]+--detach[[:space:]]+"?\$\{?ZTNCUI_COMMIT\}?"?' \
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
  'GitHub workflow passes explicit ZeroTier ref build arg' \
  'ZEROTIER_REF=' \
  .github/workflows/image-build.yml

require_match \
  'local build script passes explicit ZeroTier ref build arg' \
  '--build-arg[[:space:]]+ZEROTIER_REF=' \
  build.sh

require_match \
  'entrypoint generates planet with current zerotier-idtool instead of legacy mkworld' \
  'zerotier-idtool[[:space:]]+genmoon[[:space:]]+planet\.json' \
  patch/entrypoint.sh

reject_match \
  'Dockerfile does not depend on legacy attic/world mkworld sources' \
  'attic/world|ZEROTIER_WORLD_REF|mkworld' \
  Dockerfile

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
