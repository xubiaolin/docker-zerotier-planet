#!/bin/bash 
# debain ubuntu自动安装zerotier 并设置的为planet服务器
# addr服务器公网ip+port
 apt update -y && apt-get install -y wget curl jq build-essential git
 TAG=main
 ZEROTIER_PATH="/var/lib/zerotier-one"
 IP_ADDR4=${IP_ADDR4:-$(curl -s https://ipv4.icanhazip.com/)}
 IP_ADDR6=${IP_ADDR6:-$(curl -s https://ipv6.icanhazip.com/)}
 ZT_PORT=9993
 API_PORT=3000
 echo "********************************************************************************************************************"
 echo "**********deabin unbuntu自动安装zerotier 并设置的为planet服务器 火木木制作 放在root目录执行**********************************"
 echo "获取到的IPv4地址为: $IP_ADDR4"
 echo "获取到的IPv6地址为: $IP_ADDR6"
    if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then
        stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"
    elif [ -n "$IP_ADDR4" ]; then
        stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"
    elif [ -n "$IP_ADDR6" ]; then
        stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"
    else
        echo "IPV4或者IPV6不能同时为空，安装失败!"
        exit 1
    fi
 curl -s https://install.zerotier.com/ | bash
 identity=`cat /var/lib/zerotier-one/identity.public`
 echo "identity :$identity=============================================="
git clone https://github.com/zerotier/ZeroTierOne.git
cd ZeroTierOne 
git checkout ${TAG} 
echo "切换到tag:${TAG}" 
cd attic/world/
wget -O mkworld_custom.cpp https://raw.githubusercontent.com/xubiaolin/docker-zerotier-planet/refs/heads/master/patch/mkworld_custom.cpp
mv mkworld.cpp mkworld.cpp.bak
mv mkworld_custom.cpp mkworld.cpp
echo "开始处理，请耐心等待=============================================="
sh build.sh 
mv mkworld /var/lib/zerotier-one
cd $ZEROTIER_PATH
openssl rand -hex 16 > authtoken.secret
./zerotier-idtool generate identity.secret identity.public
./zerotier-idtool initmoon identity.public > moon.json
echo "stableEndpoints=$stableEndpoints"
jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json && mv temp.json moon.json
./zerotier-idtool genmoon moon.json && mkdir -p moons.d && cp ./*.moon ./moons.d
./mkworld
mv world.bin planet
\cp -rf ./planet /var/lib/zerotier-one
\cp -rf ./planet /root
systemctl restart zerotier-one.service
curl -O https://s3-us-west-1.amazonaws.com/key-networks/deb/ztncui/1/x86_64/ztncui_0.8.14_amd64.deb
dpkg -i ztncui_0.8.14_amd64.deb
cd /opt/key-networks/ztncui/
echo "HTTP_PORT=${API_PORT}" > ./.env
secret=`cat /var/lib/zerotier-one/authtoken.secret`
echo "ZT_TOKEN = $secret" >>./.env
echo "ZT_ADDR=127.0.0.1:9993" >>./.env
echo "NODE_ENV = production" >>./.env
echo "HTTP_ALL_INTERFACES=yes" >>./.env
systemctl restart ztncui
rm -rf /root/ZeroTierOne
echo "**********安装成功*********************************************************************************"
echo "---------------------------"
    if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then
        echo "请访问 http://${IP_ADDR4}:${API_PORT} 进行配置或者"
        echo "请访问 http://${IP_ADDR6}:${API_PORT} 进行配置"
    elif [ -n "$IP_ADDR4" ]; then
        echo "请访问 http://${IP_ADDR4}:${API_PORT} 进行配置"
    elif [ -n "$IP_ADDR6" ]; then
        echo "请访问 http://${IP_ADDR6}:${API_PORT} 进行配置"
    else
        echo "IPV4或者IPV6不能同时为空，安装失败!"
        exit 1
    fi
    echo "默认用户名：admin"
    echo "默认密码：password"
    echo "请及时修改密码"
    echo "---------------------------"
    echo "planet文件在当前安装目录下"
    echo "---------------------------"
    echo "请放行以下端口：${ZT_PORT}/tcp,${ZT_PORT}/udp，${API_PORT}/tcp"
    echo "---------------------------"

