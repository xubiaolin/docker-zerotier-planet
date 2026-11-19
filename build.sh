#!/bin/bash

upstream_owner=zerotier
upstream_repo=ZeroTierOne
DOCKER_IMAGE="xubiaolin/zerotier-planet"

latest_tag=$(curl -s "https://api.github.com/repos/$upstream_owner/$upstream_repo/tags" | jq -r '.[].name' | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1)
latest_docker_tag=$(curl -s "https://hub.docker.com/v2/repositories/${DOCKER_IMAGE}/tags/" | jq -r '.results[].name' | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1)

if [ "$latest_tag" == "$latest_docker_tag" ]; then
    echo "No new version found"
    exit 0
fi

echo "Latest tag for $upstream_owner/$upstream_repo matching latest is: $latest_tag"
docker buildx build --platform linux/arm64,linux/amd64 \
    --build-arg "TAG=${latest_tag:?missing upstream version}" \
    -t "$DOCKER_IMAGE:latest" -t "$DOCKER_IMAGE:$latest_tag" --push .
