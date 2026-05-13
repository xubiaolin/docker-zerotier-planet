#!/usr/bin/env bash
set -euo pipefail

require_file() {
  test -f "$1" || {
    echo "missing required file: $1" >&2
    exit 1
  }
}

require_grep() {
  local pattern="$1"
  local file="$2"
  grep -Eq -- "$pattern" "$file" || {
    echo "missing pattern '$pattern' in $file" >&2
    exit 1
  }
}

require_file docker-compose.yml
require_file .env.example
require_file build.sh
if [ -f deploy.sh ]; then
  echo "deploy.sh should not exist; docker compose is the supported deployment path" >&2
  exit 1
fi

require_absent() {
  local pattern="$1"
  local file="$2"
  if grep -Eq -- "$pattern" "$file"; then
    echo "unexpected pattern '$pattern' in $file" >&2
    exit 1
  fi
}

for key in DOCKER_IMAGE IP_ADDR4 IP_ADDR6 ZT_PORT API_PORT FILE_SERVER_PORT FILE_KEY ZEROTIER_DIST_DIR ZEROTIER_ZTNCUI_DIR ZEROTIER_ONE_DIR ZEROTIER_CONFIG_DIR; do
  require_grep "^${key}=" .env.example
done

require_grep '^\.env$' .gitignore
require_grep '\$\{DOCKER_IMAGE:-xubiaolin/zerotier-planet:latest\}' docker-compose.yml
require_absent 'container_name:' docker-compose.yml
require_absent '^CONTAINER_NAME=' .env.example
require_grep '\$\{ZT_PORT:-9994\}:\$\{ZT_PORT:-9994\}/tcp' docker-compose.yml
require_grep '\$\{ZT_PORT:-9994\}:\$\{ZT_PORT:-9994\}/udp' docker-compose.yml
require_grep '\$\{API_PORT:-3443\}:\$\{API_PORT:-3443\}' docker-compose.yml
require_grep '\$\{FILE_SERVER_PORT:-3000\}:\$\{FILE_SERVER_PORT:-3000\}' docker-compose.yml
require_grep '\$\{ZEROTIER_DIST_DIR:-\./data/zerotier/dist\}:/app/dist' docker-compose.yml
require_grep 'FILE_KEY=\$\{FILE_KEY:-\}' docker-compose.yml

require_grep 'path\.resolve' patch/http_server.js
require_grep 'timingSafeEqual' patch/http_server.js
require_grep 'method !== .GET. && method !== .HEAD.' patch/http_server.js
require_grep 'existingKey' patch/http_server.js
require_grep 'FILE_KEY' patch/http_server.js

require_grep 'set_env_value "\$env_file" "HTTP_ALL_INTERFACES" "true"' patch/entrypoint.sh
require_grep 'FILE_KEY' patch/entrypoint.sh
require_grep 'zerotier-idtool' Dockerfile
require_grep 'PLANET_WORLD_ID="0000000008eac90a"' patch/entrypoint.sh
require_grep '\.worldType = "planet"' patch/entrypoint.sh
require_absent 'attic/world|mkworld_custom|mkworld build' Dockerfile
require_absent '\./mkworld|world\.bin|mkmoonworld' patch/entrypoint.sh
require_grep '--build-arg TAG="\$\{latest_tag\}"' build.sh

echo "static security checks passed"
