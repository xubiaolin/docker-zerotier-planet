#!/bin/bash

apt update -y
apt install curl gnupg2 ca-certificates zip unzip build-essential git --no-install-recommends -y

export NODEJS_MAJOR=16
curl -sL -o node_inst.sh https://deb.nodesource.com/setup_${NODEJS_MAJOR}.x
bash node_inst.sh
apt install -y nodejs --no-install-recommends
apt install -y rpm build-essential rpmbuild debhelper fakeroot
apt install -y rpm alien 
apt install -y libx32stdc++-12-dev 
git clone https://github.com/key-networks/ztncui
npm install -g node-gyp pkg

if [ ! -f /usr/lib/gcc/x86_64-redhat-linux/8/libstdc++fs.a ]; then
  mkdir -p /usr/lib/gcc/x86_64-redhat-linux/8/
  cp /usr/lib/gcc/x86_64-linux-gnu/12/libstdc++fs.a /usr/lib/gcc/x86_64-redhat-linux/8/
fi
apt install -y rubygems
gem install fpm

sh zh.sh

cd ztncui/build

./build.sh
