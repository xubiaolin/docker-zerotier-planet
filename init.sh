echo "update source"
echo "deb http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
"> /etc/apt/sources.list
apt update 
apt upgrade -y
apt install -y tzdata 
ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime 
echo ${TZ} > /etc/timezone 
dpkg-reconfigure --frontend noninteractive tzdata 
rm -rf /var/lib/apt/lists/*

apt update
apt install git python3 npm make curl  -y
npm config set registry http://registry.npm.taobao.org && npm install -g node-gyp
curl -s https://install.zerotier.com |  bash
cd /opt && git clone -v http://gh-proxy.markxu.vip/https://github.com/key-networks/ztncui.git
cd /opt && git clone -v http://gh-proxy.markxu.vip/https://github.com/zerotier/ZeroTierOne.git

cd /opt/ztncui/src 
npm install 
cp -pv ./etc/default.passwd ./etc/passwd
echo 'HTTP_PORT=3443' >.env
echo 'NODE_ENV=production' >>.env
echo 'HTTP_ALL_INTERFACES=true' >>.env

cd /var/lib/zerotier-one && zerotier-idtool initmoon identity.public > moon.json
cd /app/patch && python3 patch.py
cd /var/lib/zerotier-one && zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d
cd /opt/ZeroTierOne/attic/world/ && sh build.sh
sleep 5s

cd /opt/ZeroTierOne/attic/world/ && ./mkworld
mkdir /app/bin -p && cp world.bin /app/bin/planet

service zerotier-one restart 
