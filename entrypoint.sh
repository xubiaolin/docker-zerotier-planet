#!/bin/sh

# make moon
# set -x

# if [ -f "/app/init.flag" ]; then
#     echo "/app/init.flag exists, start directly"

#     echo "start ztncui and zerotier"
#     sh -c "cd /var/lib/zerotier-one && ./zerotier-one -p$(cat /app/zerotier-one.port) -d; cd /app/ztncui/src; npm start"
#     return 0
# fi

# mkdir -p /app/ztncui
# if [ "$(ls -A /app/ztncui)" ]; then
#     echo "/app/ztncui is not empty, start directly"
# else
#     echo "/app/ztncui is empty, init data"
#     cp -r /bak/ztncui/* /app/ztncui/
# fi

# mkdir -p /var/lib/zerotier-one
# if [ "$(ls -A /var/lib/zerotier-one)" ]; then
#     echo "/var/lib/zerotier-one is not empty, start directly"
# else
#     echo "/var/lib/zerotier-one is empty, init data"
#     cp -r /bak/zerotier-one/* /var/lib/zerotier-one/
# fi

# cd /var/lib/zerotier-one
# echo "start mkmoonworld"

# ./zerotier-idtool initmoon identity.public >moon.json

# if [ -z "$IP_ADDR4" ]; then IP_ADDR4=$(curl -s https://ipv4.icanhazip.com/); fi
# if [ -z "$IP_ADDR6" ]; then IP_ADDR6=$(curl -s https://ipv6.icanhazip.com/); fi

# echo "IP_ADDR4=$IP_ADDR4"
# echo "IP_ADDR6=$IP_ADDR6"

# ZT_PORT=$(cat /app/zerotier-one.port)
# API_PORT=$(cat /app/ztncui.port)

# echo "ZT_PORT=$ZT_PORT"
# echo "API_PORT=$API_PORT"

# if [ -z "$IP_ADDR4" ]; then stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"; fi
# if [ -z "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"; fi
# if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"; fi
# if [ -z "$IP_ADDR4" ] && [ -z "$IP_ADDR6" ]; then
#     echo "IP_ADDR4 and IP_ADDR6 are both empty!"
#     exit 1
# fi

# echo "stableEndpoints=$stableEndpoints"

# jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json >temp.json && mv temp.json moon.json
# ./zerotier-idtool genmoon moon.json && mkdir -p moons.d && cp ./*.moon ./moons.d

# wget "https://github.com/kaaass/ZeroTierOne/releases/download/mkmoonworld-1.0/mkmoonworld-x86_64"
# chmod +x ./mkmoonworld-x86_64
# ./mkmoonworld-x86_64 moon.json

# mkdir -p /app/dist/
# mv world.bin /app/dist/planet
# cp *.moon /app/dist/
# echo -e "mkmoonworld success!\n"

# echo "config ztncui"
# cd /app/ztncui/src
# echo "HTTP_PORT=${API_PORT}" >.env &&
#     echo 'NODE_ENV=production' >>.env &&
#     echo 'HTTP_ALL_INTERFACES=true' >>.env &&
#     echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env && echo "${ZT_PORT}" >/app/zerotier-one.port &&
#     cp -v etc/default.passwd etc/passwd && TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) &&
#     echo "ZT_TOKEN=$TOKEN" >>.env &&
#     echo "make ztncui success!"

# echo "start ztncui and zerotier"
# touch /app/init.flag
# sh -c "cd /var/lib/zerotier-one && ./zerotier-one -p$(cat /app/zerotier-one.port) -d; cd /app/ztncui/src; npm start"


#!/bin/sh

set -x 

function start() {
    echo "start ztncui and zerotier"
    touch /app/init.flag
    cd /var/lib/zerotier-one && ./zerotier-one -p$(cat /app/zerotier-one.port) -d || exit 1
    cd /app/ztncui/src && npm start || exit 1
}

# function check_flag() {
#     if [ -f "/app/init.flag" ]; then
#         echo "/app/init.flag exists, start directly"
#         return 0
#     fi
# }

func check_ztncui() {
    mkdir -p /app/ztncui
    if [ "$(ls -A /app/ztncui)" ]; then
        echo "/app/ztncui is not empty, start directly"
    else
        echo "/app/ztncui is empty, init data"
        cp -r /bak/ztncui/* /app/ztncui/

        echo "config ztncui"
        cd /app/ztncui/src
        echo "HTTP_PORT=${API_PORT}" >.env &&
            echo 'NODE_ENV=production' >>.env &&
            echo 'HTTP_ALL_INTERFACES=true' >>.env &&
            echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env && echo "${ZT_PORT}" >/app/zerotier-one.port &&
            cp -v etc/default.passwd etc/passwd && TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) &&
            echo "ZT_TOKEN=$TOKEN" >>.env &&
            echo "make ztncui success!"
    fi
}

func check_zerotier() {
    mkdir -p /var/lib/zerotier-one
    if [ "$(ls -A /var/lib/zerotier-one)" ]; then
        echo "/var/lib/zerotier-one is not empty, start directly"
    else
        echo "/var/lib/zerotier-one is empty, init data"
        cp -r /bak/zerotier-one/* /var/lib/zerotier-one/

        cd /var/lib/zerotier-one
        echo "start mkmoonworld"

        ./zerotier-idtool initmoon identity.public >moon.json

        if [ -z "$IP_ADDR4" ]; then IP_ADDR4=$(curl -s https://ipv4.icanhazip.com/); fi
        if [ -z "$IP_ADDR6" ]; then IP_ADDR6=$(curl -s https://ipv6.icanhazip.com/); fi

        echo "IP_ADDR4=$IP_ADDR4"
        echo "IP_ADDR6=$IP_ADDR6"

        ZT_PORT=$(cat /app/zerotier-one.port)
        API_PORT=$(cat /app/ztncui.port)

        echo "ZT_PORT=$ZT_PORT"
        echo "API_PORT=$API_PORT"

        if [ -z "$IP_ADDR4" ]; then stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"; fi
        if [ -z "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"; fi
        if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"; fi
        if [ -z "$IP_ADDR4" ] && [ -z "$IP_ADDR6" ]; then
            echo "IP_ADDR4 and IP_ADDR6 are both empty!"
            exit 1
        fi

        echo "stableEndpoints=$stableEndpoints"

        jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json >temp.json && mv temp.json moon.json
        ./zerotier-idtool genmoon moon.json && mkdir -p moons.d && cp ./*.moon ./moons.d

        wget "https://github.com/kaaass/ZeroTierOne/releases/download/mkmoonworld-1.0/mkmoonworld-x86_64"
        chmod +x ./mkmoonworld-x86_64
        ./mkmoonworld-x86_64 moon.json

        mkdir -p /app/dist/
        mv world.bin /app/dist/planet
        cp *.moon /app/dist/
        echo -e "mkmoonworld success!\n"
    fi
}


check_ztncui
check_zerotier

start