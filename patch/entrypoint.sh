#!/bin/sh

set -x 

# 配置路径和端口
ZEROTIER_PATH="/var/lib/zerotier-one"
APP_PATH="/app"
CONFIG_PATH="${APP_PATH}/config"
BACKUP_PATH="/bak"
ZTNCUI_PATH="${APP_PATH}/ztncui"
ZTNCUI_SRC_PATH="${ZTNCUI_PATH}/src"

# 启动 ZeroTier 和 ztncui
function start() {
    echo "Start ztncui and zerotier"
    cd $ZEROTIER_PATH && ./zerotier-one -p$(cat ${CONFIG_PATH}/zerotier-one.port) -d || exit 1
    nohup node ${APP_PATH}/http_server.js &> ${APP_PATH}/server.log & 
    # 新增变量和语句,填写域名则根据域名IP自动更新planet和moon
    if [ -n "${DOMAIN}" ]; then
        echo "启动域名解析更新功能"
        nohup sh ${APP_PATH}/update_moon_planet.sh >/dev/null 2>log & 
    fi
    cd $ZTNCUI_SRC_PATH && npm start || exit 1
}

# 检查文件服务器端口配置文件
function check_file_server() {
    if [ ! -f "${CONFIG_PATH}/file_server.port" ]; then
        echo "file_server.port does not exist, generating it"
        echo "${FILE_SERVER_PORT}" > ${CONFIG_PATH}/file_server.port
    else
        echo "file_server.port exists, reading it"
        FILE_SERVER_PORT=$(cat ${CONFIG_PATH}/file_server.port)
    fi
    echo "${FILE_SERVER_PORT}"

    # 比对文件服务器密钥
    key_file="${CONFIG_PATH}/file_server.key"

    if [ ! -f "$key_file" ]; then
        [ -z "$SECRET_KEY" ] && SECRET_KEY=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
        echo "$SECRET_KEY" > "$key_file"
    else
        if [ -n "$SECRET_KEY" ] && [ "$SECRET_KEY" != "$(cat "$key_file" 2>/dev/null)" ]; then
            echo "$SECRET_KEY" > "$key_file"
        fi
    fi
    echo "文件服务器密钥: $SECRET_KEY"
}

# 初始化 ZeroTier 数据
function init_zerotier_data() {
    echo "Initializing ZeroTier data"
    echo "${ZT_PORT}" > ${CONFIG_PATH}/zerotier-one.port
    cp -r ${BACKUP_PATH}/zerotier-one/* $ZEROTIER_PATH

    cd $ZEROTIER_PATH
    openssl rand -hex 16 > authtoken.secret
    ./zerotier-idtool generate identity.secret identity.public
    ./zerotier-idtool initmoon identity.public > moon.json
    mkdir -p ${APP_PATH}/dist/
    if  [[ -n "$DOMAIN" ]]; then
        if command -v dig >/dev/null 2>&1; then
            IP_ADDR4=$(dig +short A "$DOMAIN" | head -n 1)
            IP_ADDR6=$(dig +short AAAA "$DOMAIN" | head -n 1)
        else
            # fallback 使用 nslookup
            IP_ADDR4=$(nslookup "$DOMAIN" | awk '/^Address: / && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $2}' | head -n 1)
            IP_ADDR6=$(nslookup "$DOMAIN" | awk '/^Address: / && $2 ~ /^[0-9a-fA-F:]+$/ {print $2}' | head -n 1)
        fi
        if [ -z "$IP_ADDR4" ] && [ -z "$IP_ADDR6" ]; then
            print_message "域名解析失败,无法获取IP地址"
            exit 1
        fi
        echo "${IP_ADDR4},${IP_ADDR6}" > ${APP_PATH}/dist/ips
    else
        IP_ADDR4=${IP_ADDR4:-$(curl -s https://ipv4.icanhazip.com/)}
        IP_ADDR6=${IP_ADDR6:-$(curl -s https://ipv6.icanhazip.com/)}
    fi

    echo "IP_ADDR4=$IP_ADDR4"
    echo "IP_ADDR6=$IP_ADDR6"
    ZT_PORT=$(cat ${CONFIG_PATH}/zerotier-one.port)
    echo "ZT_PORT=$ZT_PORT"

    if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then
        stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"
    elif [ -n "$IP_ADDR4" ]; then
        stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"
    elif [ -n "$IP_ADDR6" ]; then
        stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"
    else
        echo "IPV4 或 IPV6 不能为空"
        exit 1
    fi
    echo "$DOMAIN" > ${CONFIG_PATH}/domain
    echo "$IP_ADDR4" > ${CONFIG_PATH}/ip_addr4
    echo "$IP_ADDR6" > ${CONFIG_PATH}/ip_addr6
    echo "stableEndpoints=$stableEndpoints"

    jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json && mv temp.json moon.json
    ./zerotier-idtool genmoon moon.json && mkdir -p moons.d && cp ./*.moon ./moons.d

    ./mkworld
    if [ $? -ne 0 ]; then
        echo "mkmoonworld failed!"
        exit 1
    fi
    mv world.bin ${APP_PATH}/dist/planet
    cp *.moon ${APP_PATH}/dist/
    echo "mkmoonworld success!"
}

# 检查并初始化 ZeroTier
function check_zerotier() {
    mkdir -p $ZEROTIER_PATH
    if [ "$(ls -A $ZEROTIER_PATH)" ]; then
        echo "$ZEROTIER_PATH is not empty, starting directly"
    else
        init_zerotier_data
    fi
}

# 初始化 ztncui 数据
function init_ztncui_data() {
    echo "Initializing ztncui data"
    cp -r ${BACKUP_PATH}/ztncui/* $ZTNCUI_PATH

    echo "Configuring ztncui"
    mkdir -p ${CONFIG_PATH}
    echo "${API_PORT}" > ${CONFIG_PATH}/ztncui.port
    cd $ZTNCUI_SRC_PATH
    echo "HTTP_PORT=${API_PORT}" > .env
    echo 'NODE_ENV=production' >> .env
    echo 'HTTP_ALL_INTERFACES=true' >> .env
    echo "ZT_ADDR=localhost:${ZT_PORT}" >> .env
    cp -v etc/default.passwd etc/passwd
    TOKEN=$(cat ${ZEROTIER_PATH}/authtoken.secret)
    echo "ZT_TOKEN=$TOKEN" >> .env
    echo "ztncui configuration successful!"
}

# 检查并初始化 ztncui
function check_ztncui() {
    mkdir -p $ZTNCUI_PATH
    if [ "$(ls -A $ZTNCUI_PATH)" ]; then
        echo "${API_PORT}" > ${CONFIG_PATH}/ztncui.port
        echo "$ZTNCUI_PATH is not empty, starting directly"
    else
        init_ztncui_data
    fi
}

check_file_server
check_zerotier
check_ztncui
start
