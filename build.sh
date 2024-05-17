#!/bin/bash

USER=zerotier
REPO=ZeroTierOne

latest_tag=$(curl -s "https://api.github.com/repos/$USER/$REPO/tags" | jq -r '.[].name' | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1)

echo "Latest tag for $USER/$REPO matching latest is: $latest_tag"

docker build --build-arg TAG="$latest_tag" -t "xubiaolin/zerotier-planet:$latest_tag" .
docker tag "xubiaolin/zerotier-planet:$latest_tag" "xubiaolin/zerotier-planet:latest"
