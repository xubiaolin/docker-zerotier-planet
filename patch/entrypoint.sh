#!/bin/sh

set -x 

function start() {
    echo "start ztncui and zerotier"
    cd /var/lib/zerotier-one && ./zerotier-one -p$(cat /app/config/zerotier-one.port) -d || exit 1
    nohup node /app/http_server.js &> /app/server.log & 
    cd /app/ztncui/src && npm start || exit 1
}

function check_file_server(){
    if [ ! -f "/app/config/file_server.port" ]; then
        echo "file_server.port is not exist, generate it"
        echo "${FILE_SERVER_PORT}" >/app/config/file_server.port
        echo "${FILE_SERVER_PORT}"
    else
        echo "file_server.port is exist, read it"
        FILE_SERVER_PORT=$(cat /app/config/file_server.port)
        echo "${FILE_SERVER_PORT}"
    fi
}

function check_zerotier() {
    mkdir -p /var/lib/zerotier-one
    if [ "$(ls -A /var/lib/zerotier-one)" ]; then
        echo "/var/lib/zerotier-one is not empty, start directly"
    else    
        mkdir -p /app/config
        echo "/var/lib/zerotier-one is empty, init data"
        echo "${ZT_PORT}" >/app/config/zerotier-one.port
        cp -r /bak/zerotier-one/* /var/lib/zerotier-one/

        cd /var/lib/zerotier-one
        echo "start mkmoonworld"
        openssl rand -hex 16 > authtoken.secret

        ./zerotier-idtool generate identity.secret identity.public
        ./zerotier-idtool initmoon identity.public >moon.json

        if [ -z "$IP_ADDR4" ]; then IP_ADDR4=$(curl -s https://ipv4.icanhazip.com/); fi
        if [ -z "$IP_ADDR6" ]; then IP_ADDR6=$(curl -s https://ipv6.icanhazip.com/); fi

        echo "IP_ADDR4=$IP_ADDR4"
        echo "IP_ADDR6=$IP_ADDR6"

        ZT_PORT=$(cat /app/config/zerotier-one.port)

        echo "ZT_PORT=$ZT_PORT"

        if [ -z "$IP_ADDR4" ]; then stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"; fi
        if [ -z "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"; fi
        if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"; fi
        if [ -z "$IP_ADDR4" ] && [ -z "$IP_ADDR6" ]; then
            echo "IP_ADDR4 and IP_ADDR6 are both empty!"
            exit 1
        fi

        echo "$IP_ADDR4">/app/config/ip_addr4
        echo "$IP_ADDR6">/app/config/ip_addr6

        echo "stableEndpoints=$stableEndpoints"

        jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json >temp.json && mv temp.json moon.json
        ./zerotier-idtool genmoon moon.json && mkdir -p moons.d && cp ./*.moon ./moons.d

        ./mkworld moon.json
        if [ $? -ne 0 ]; then
            echo "mkmoonworld failed!"
            exit 1
        fi

        mkdir -p /app/dist/
        mv world.bin /app/dist/planet
        cp *.moon /app/dist/
        echo -e "mkmoonworld success!\n"
    fi
}

function check_ztncui() {
    mkdir -p /app/ztncui
    if [ "$(ls -A /app/ztncui)" ]; then
        echo "${API_PORT}" >/app/config/ztncui.port
        echo "/app/ztncui is not empty, start directly"
    else
        echo "/app/ztncui is empty, init data"
        cp -r /bak/ztncui/* /app/ztncui/

        echo "config ztncui"
        mkdir -p /app/config
        echo "${API_PORT}" >/app/config/ztncui.port
        cd /app/ztncui/src
        echo "HTTP_PORT=${API_PORT}" >.env &&
            echo 'NODE_ENV=production' >>.env &&
            echo 'HTTP_ALL_INTERFACES=true' >>.env &&
            echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env && echo "${ZT_PORT}" >/app/config/zerotier-one.port &&
            cp -v etc/default.passwd etc/passwd && TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) &&
            echo "ZT_TOKEN=$TOKEN" >>.env &&
            echo "make ztncui success!"
    fi
}

check_file_server
check_zerotier
check_ztncui

start