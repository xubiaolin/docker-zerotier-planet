#!/bin/sh

# 配置变量
APP_PATH="/app"
FILE_PATH=${APP_PATH}/dist
CONFIG_PATH="${APP_PATH}/config"
LOG_FILE_PATH="${APP_PATH}/update_moon_planet.log"
CHECK_INTERVAL=${CHECK_INTERVAL: -60}
LOG_MAX_LINES=${LOG_MAX_LINES: -3000}
ZEROTIER_PATH="/var/lib/zerotier-one"

print_message(){
    message="$1"

    # 创建日志文件（如果不存在）
    touch "$LOG_FILE_PATH"

    # 检查当前行数并删除最旧行（如果超过限制）
    current_lines=$(wc -l < "$LOG_FILE_PATH")
    if [ "$current_lines" -ge "$LOG_MAX_LINES" ]; then
        sed -i '1,50d' "$LOG_FILE_PATH"
    fi
    # 获取当前时间戳
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    # 写入新日志（格式：时间戳 + 消息）
    echo "$current_time - $message" >> "$LOG_FILE_PATH"
}

# 重新生成planet文件
update_moon_planet() {
	print_message "开始检查更新"
    print_message "开始解析域名获取IP地址"
	# 优先尝试使用 dig 获取 IP
    if command -v dig >/dev/null 2>&1; then
        ipv4=$(dig +short A "$DOMAIN" | head -n 1)
        ipv6=$(dig +short AAAA "$DOMAIN" | head -n 1)
    else
        # fallback 使用 nslookup
        ipv4=$(nslookup "$DOMAIN" | awk '/^Address: / && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $2}' | head -n 1)
        ipv6=$(nslookup "$DOMAIN" | awk '/^Address: / && $2 ~ /^[0-9a-fA-F:]+$/ {print $2}' | head -n 1)
    fi
    if [ -z "$ipv4" ] && [ -z "$ipv6" ]; then
        print_message "域名解析失败,无法获取IP地址"
        return 1
    fi
	
	current_ipv4=$(cat ${CONFIG_PATH}/ip_addr4)
	current_ipv6=$(cat ${CONFIG_PATH}/ip_addr6)
	if [ "${ipv4}" == "${current_ipv4}" ] && [ "${ipv6}" == "${current_ipv6}" ]; then
        print_message "IP地址未变更"
		return 0
    fi
	echo "新IP地址为：${ipv4},${ipv6}"
	echo "当前IP地址为：${current_ipv4},${current_ipv6}"
	print_message "IP产生变动，重新编译planet\monn文件"
	zt_port=$(cat ${CONFIG_PATH}/zerotier-one.port)
	if [ -n "$ipv4" ] && [ -n "$ipv6" ]; then
		stableEndpoints="[\"$ipv4/${zt_port}\",\"$ipv6/${zt_port}\"]"
	elif [ -n "$ipv4" ]; then
		stableEndpoints="[\"$ipv4/${zt_port}\"]"
	elif [ -n "$ipv6" ]; then
		stableEndpoints="[\"$ipv6/${zt_port}\"]"
	fi
	print_message "开始编译..."
	
	cd $ZEROTIER_PATH
	jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json && mv temp.json moon.json
	
	rm -rf moons.d/* && rm -rf moons.d/* && rm ./*.moon
	
	./zerotier-idtool genmoon moon.json && cp ./*.moon ./moons.d

	./mkworld
	if [ $? -ne 0 ]; then
		print_message "编译失败!"
		return 1
	fi
	
	rm -rf ${APP_PATH}/dist/*
	mv world.bin ${APP_PATH}/dist/planet
	cp *.moon ${APP_PATH}/dist/
	echo "$ipv4" > ${CONFIG_PATH}/ip_addr4
    echo "$ipv6" > ${CONFIG_PATH}/ip_addr6
    echo "${ipv4},${ipv6}" > ${FILE_PATH}/ips
	print_message "编译成功"
	
	print_message "重启 zerotier-on 服务"
    kill $(ps -ef | grep "./zerotier-one")
	cd $ZEROTIER_PATH && ./zerotier-one -p$(cat ${CONFIG_PATH}/zerotier-one.port) -d || exit 1
	print_message "重启完成"
}

while true; do
    update_moon_planet
    sleep $CHECK_INTERVAL
done