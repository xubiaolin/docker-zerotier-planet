#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ZEROTIER_VERSION=${ZEROTIER_VERSION:-1.16.2}
IMAGE=${IMAGE:-zerotier-planet:local}
PLATFORM=${PLATFORM:-linux/amd64}
PROJECT_REVISION=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)

docker buildx build \
    --build-arg "PROJECT_REVISION=$PROJECT_REVISION" \
    --build-arg "ZEROTIER_VERSION=$ZEROTIER_VERSION" \
    --load \
    --platform "$PLATFORM" \
    --tag "$IMAGE" \
    "$PROJECT_ROOT"
