#!/bin/bash

apt update -y
apt install curl gnupg2 ca-certificates zip unzip build-essential git --no-install-recommends -y

export NODEJS_MAJOR=16
curl -sL -o node_inst.sh https://deb.nodesource.com/setup_${NODEJS_MAJOR}.x
bash node_inst.sh
apt install -y nodejs --no-install-recommends
git clone https://github.com/key-networks/ztncui
npm install -g node-gyp pkg


apt install rpm build-essential rpmbuild debhelper fakeroot -y
apt install libx32stdc++-12-dev -y
mkdir -p /usr/lib/gcc/x86_64-redhat-linux/8/
cp /usr/lib/gcc/x86_64-linux-gnu/12/libstdc++fs.a /usr/lib/gcc/x86_64-redhat-linux/8/

sudo apt-get install rubygems
gem install fpm

sh zh.sh

cd ztncui/build

./build.sh
