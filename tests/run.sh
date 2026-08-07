#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_ROOT"

bash -n deploy.sh build.sh scripts/deploy/*.sh tests/integration/*.sh
dash -n container/*.sh container/lib/*.sh
node --test tests/unit/file-server.test.js
docker compose --env-file .env.example --file compose.yaml config --quiet

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck deploy.sh build.sh scripts/deploy/*.sh container/*.sh container/lib/*.sh tests/integration/*.sh
fi
if command -v shfmt >/dev/null 2>&1; then
    shfmt -d -i 4 -ci deploy.sh build.sh scripts/deploy container tests
fi
if command -v bats >/dev/null 2>&1; then
    bats tests/unit/*.bats
fi
