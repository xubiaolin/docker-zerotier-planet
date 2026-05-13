#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local pattern="$1"
  local file="$2"

  grep -Eq -- "$pattern" "$file" || {
    echo "missing pattern '$pattern' in $file" >&2
    exit 1
  }
}

assert_not_contains() {
  local pattern="$1"
  local file="$2"

  if grep -Eq -- "$pattern" "$file"; then
    echo "unexpected pattern '$pattern' in $file" >&2
    exit 1
  fi
}

test_build_script_handles_missing_dockerhub_results_and_installs_binfmt() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail

url="${@: -1}"
case "$url" in
  https://api.github.com/repos/zerotier/ZeroTierOne/tags*)
    printf '%s\n' '[{"name":"1.16.0"},{"name":"1.14.2"}]'
    ;;
  https://hub.docker.com/v2/repositories/xubiaolin/zerotier-planet-v2/tags/*)
    printf '%s\n' '{"message":"object not found"}'
    ;;
  *)
    echo "unexpected curl url: $url" >&2
    exit 1
    ;;
esac
CURL
  chmod +x "$tmp/bin/curl"

  cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail

log="${DOCKER_STUB_LOG:?}"

case "$*" in
  "buildx ls")
    cat <<'LS'
NAME/NODE     DRIVER/ENDPOINT   STATUS    BUILDKIT   PLATFORMS
default*      docker
 \_ default    \_ default       running   v0.28.1    linux/amd64
LS
    ;;
  "run --privileged --rm tonistiigi/binfmt --install arm64,amd64")
    printf '%s\n' "$*" >> "$log"
    ;;
  buildx\ build\ *)
    printf '%s\n' "$*" >> "$log"
    ;;
  *)
    echo "unexpected docker args: $*" >&2
    exit 1
    ;;
esac
DOCKER
  chmod +x "$tmp/bin/docker"

  set +e
  (
    cd "$REPO_ROOT"
    PATH="$tmp/bin:$PATH" DOCKER_STUB_LOG="$tmp/docker.log" ./build.sh
  ) > "$tmp/output" 2>&1
  local status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    cat "$tmp/output" >&2
    exit "$status"
  fi

  assert_not_contains 'Cannot iterate over null' "$tmp/output"
  assert_contains 'tonistiigi/binfmt --install arm64,amd64' "$tmp/docker.log"
  assert_contains 'buildx build --platform linux/arm64,linux/amd64' "$tmp/docker.log"
  assert_contains '-t xubiaolin/zerotier-planet-v2:latest' "$tmp/docker.log"
  assert_contains '-t xubiaolin/zerotier-planet-v2:1\.16\.0' "$tmp/docker.log"
}

test_build_script_handles_missing_dockerhub_results_and_installs_binfmt

echo "build script checks passed"
