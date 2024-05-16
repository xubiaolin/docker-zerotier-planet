#!/bin/bash

USER=zerotier
REPO=ZeroTierOne

latest_tag=$(curl -s "https://api.github.com/repos/$USER/$REPO/tags" | jq -r '.[].name' | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1)

echo "Latest tag for $USER/$REPO matching the format digit.digit.digit is: $latest_tag"

docker build --build-arg TAG="$latest_tag" -t "xubiaolin/zerotier-planet:$latest_tag" .
