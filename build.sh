#!/usr/bin/env bash
set -euo pipefail

USER=zerotier
REPO=ZeroTierOne
DOCKER_IMAGE="${DOCKER_IMAGE:-xubiaolin/zerotier-planet-v2}"
PLATFORMS="${PLATFORMS:-linux/arm64,linux/amd64}"

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

latest_semver_tag() {
    grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1 || true
}

get_latest_zerotier_tag() {
    curl -fsSL "https://api.github.com/repos/$USER/$REPO/tags?per_page=100" \
        | jq -r 'if type == "array" then .[].name else empty end' \
        | latest_semver_tag
}

get_latest_docker_tag() {
    curl -sS "https://hub.docker.com/v2/repositories/${DOCKER_IMAGE}/tags/?page_size=100" \
        | jq -r '(.results // [])[].name' \
        | latest_semver_tag
}

ensure_binfmt_for_platforms() {
    case ",$PLATFORMS," in
        *,linux/arm64,*)
            if ! docker buildx ls | grep -Eq 'linux/arm64|linux/arm/v8'; then
                echo "linux/arm64 is not available in docker buildx; installing binfmt handlers..."
                docker run --privileged --rm tonistiigi/binfmt --install arm64,amd64
            fi
            ;;
    esac
}

require_command curl
require_command jq
require_command docker

latest_tag="$(get_latest_zerotier_tag)"
latest_docker_tag="$(get_latest_docker_tag)"

if [ -z "$latest_tag" ]; then
    echo "No ZeroTier version tag found for $USER/$REPO" >&2
    exit 1
fi

if [ "$latest_tag" == "$latest_docker_tag" ]; then
    echo "No new version found"
    exit 0
fi

echo "Latest tag for $USER/$REPO matching latest is: $latest_tag"
ensure_binfmt_for_platforms
docker buildx build --platform "$PLATFORMS" --build-arg TAG="${latest_tag}" -t "$DOCKER_IMAGE":latest -t "${DOCKER_IMAGE}:${latest_tag}" --push .
