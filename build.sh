#!/bin/bash

DOCKER_IMAGE="registry.cn-hangzhou.aliyuncs.com/dubux/zerotier-planet"


 
docker buildx build --platform linux/arm64,linux/amd64 -t "$DOCKER_IMAGE":latest --push .
