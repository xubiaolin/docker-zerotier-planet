#!/bin/bash

function install(){
    echo "开始安装..."

    ZT_PORT=9994
    API_PORT=3443
    FILE_PORT=3000

    read -p "请输入zerotier-planet要使用的端口号,例如9994: " ZT_PORT
    while [[ ! "$ZT_PORT" =~ ^[0-9]+$ ]]; do
        read -p "端口号必须是数字，请重新输入: " ZT_PORT
    done

    netstat -anp | grep ${ZT_PORT}
    if [ $? -eq 0 ]; then
        echo "端口${ZT_PORT}已被占用，请重新输入"
        exit 1
    fi

    read -p "请输入zerotier-planet的API端口号,例如3443: " API_PORT
    while [[ ! "$API_PORT" =~ ^[0-9]+$ ]]; do
        read -p "端口号必须是数字，请重新输入: " API_PORT
    done

    netstat -anp | grep ${API_PORT}
    if [ $? -eq 0 ]; then
        echo "端口${API_PORT}已被占用，请重新输入"
        exit 1
    fi


    read -p "请输入zerotier-planet的FILE端口号,例如3000: " FILE_PORT
    while [[ ! "$FILE_PORT" =~ ^[0-9]+$ ]]; do
        read -p "端口号必须是数字，请重新输入: " FILE_PORT
    done

    netstat -anp | grep ${FILE_PORT}
    if [ $? -eq 0 ]; then
        echo "端口${FILE_PORT}已被占用，请重新输入"
        exit 1
    fi


    read -p "是否自动获取公网IP地址?(y/n)" use_auto_ip
    use_auto_ip=${use_auto_ip:-y}
    if [[ "$use_auto_ip" =~ ^[Yy]$ ]]; then
        ipv4=$(curl -s https://ipv4.icanhazip.com/)
        ipv6=$(curl -s https://ipv6.icanhazip.com/)
        echo "获取到的IPv4地址为: $ipv4"
        echo "获取到的IPv6地址为: $ipv6"

        read -p "是否使用上面获取到的IP地址?(y/n)" use_auto_ip_result
        use_auto_ip_result=${use_auto_ip_result:-y}
        if [[ "$use_auto_ip_result" =~ ^[Nn]$ ]]; then
        read -p "请输入IPv4地址: " ipv4
        read -p "请输入IPv6地址(可留空): " ipv6
        fi
    else
        # 要求用户手动输入IP地址
        read -p "请输入IPv4地址: " ipv4
        read -p "请输入IPv6地址(可留空): " ipv6
    fi

    #汇总信息
    echo "---------------------------"
    echo "使用的端口号为：${ZT_PORT}"
    echo "API端口号为：${API_PORT}"
    echo "FILE端口号为：${FILE_PORT}"
    echo "IPv4地址为：${ipv4}"
    echo "IPv6地址为：${ipv6}"
    echo "---------------------------"

    docker run -d --name myztplanet\
     -p ${ZT_PORT}:${ZT_PORT} \
     -p ${ZT_PORT}:${ZT_PORT}/udp \
     -p ${API_PORT}:${API_PORT}\
     -p ${FILE_PORT}:${FILE_PORT} \
     -e ZT_PORT=${ZT_PORT} \
     -e API_PORT=${API_PORT} \
     -e FILE_SERVER_PORT=${FILE_PORT} \
     -v /data/zerotier/dist:/app/dist \
     -v /data/zerotier/ztncui:/app/ztncui\
     -v /data/zerotier/one:/var/lib/zerotier-one\
     -v /data/ports:/app/ports\
     xubiaolin/zerotier-planet:latest

     sleep 10

    KEY=$(docker exec -it myztplanet sh -c 'cat /app/config/file_server.key')
    MOON_NAME=$(docker exec -it myztplanet sh -c 'ls /app/dist |grep moon')

    echo "安装完成"
    echo "---------------------------"
    echo "请访问 http://${ipv4}:${API_PORT} 进行配置"
    echo "默认用户名：admin"
    echo "默认密码：password"
    echo "请及时修改密码"
    echo "---------------------------"
    echo "moon配置和planet配置在 /data/zerotier/dist 目录下"
    echo ""
    echo "planet文件下载： http://${ipv4}:${FILE_PORT}/planet?key=${KEY} "
    echo "moon文件下载： http://${ipv4}:${FILE_PORT}/${MOON_NAME}?key=${KEY} "
}

function info(){
    docker inspect myztplanet >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "容器myztplanet不存在，请先安装"
        exit 1
    fi

    ipv4=$(docker exec -it myztplanet sh -c 'cat /app/config/ip_addr4')
    ipv6=$(docker exec -it myztplanet sh -c 'cat /app/config/ip_addr6')
    API_PORT=$(docker exec -it myztplanet sh -c 'cat /app/ports/ztncui.port')
    FILE_PORT=$(docker exec -it myztplanet sh -c 'cat /app/ports/file_server.port')
    MOON_NAME=$(docker exec -it myztplanet sh -c 'ls /app/dist |grep moon')
    ZT_PORT=$(docker exec -it myztplanet sh -c 'cat /app/config/zerotier-one.port')

    echo "---------------------------"
    echo "以下端口的tcp和udp协议请放行：${ZT_PORT}，${API_PORT}，${FILE_PORT}"
    echo "---------------------------"
    echo "请访问 http://${ipv4}:${API_PORT} 进行配置"
    echo "默认用户名：admin"
    echo "默认密码：password"
    echo "请及时修改密码"
    echo "---------------------------"
    echo "moon配置和planet配置在 /data/zerotier/dist 目录下"
    echo ""
    echo "planet文件下载： http://${ipv4}:${FILE_PORT}/planet?key=${KEY} "
    echo "moon文件下载： http://${ipv4}:${FILE_PORT}/${MOON_NAME}?key=${KEY} "

}

function uninstall(){
    echo "开始卸载..."

    docker stop myztplanet
    docker rm myztplanet
    docker rmi xubiaolin/zerotier-planet:latest

    #是否删除数据,默认不删除
    read -p "是否删除数据?(y/n)" delete_data
    delete_data=${delete_data:-n}
    if [[ "$delete_data" =~ ^[Yy]$ ]]; then
        rm -rf /data/zerotier
    fi

    echo "卸载完成"
}

function update(){
    echo "开始更新..."

    if [ ! -d "/data/zerotier" ]; then
        echo "目录/data/zerotier不存在，无法更新"
        exit 0 
    fi

    ipv4=$(docker exec -it myztplanet sh -c 'cat /app/config/ip_addr4')
    ipv6=$(docker exec -it myztplanet sh -c 'cat /app/config/ip_addr6')
    API_PORT=$(docker exec -it myztplanet sh -c 'cat /app/config/ztncui.port')
    FILE_PORT=$(docker exec -it myztplanet sh -c 'cat /app/config/file_server.port')
    ZT_PORT=$(docker exec -it myztplanet sh -c 'cat /app/config/zerotier-one.port')
    
    docker stop myztplanet 
    docker pull xubiaolin/zerotier-planet:latest
    docker rm myztplanet

    docker run -d --name myztplanet\
     -p ${ZT_PORT}:${ZT_PORT} \
     -p ${ZT_PORT}:${ZT_PORT}/udp \
     -p ${API_PORT}:${API_PORT}\
     -p ${FILE_PORT}:${FILE_PORT} \
     -e ZT_PORT=${ZT_PORT} \
     -e API_PORT=${API_PORT} \
     -e FILE_SERVER_PORT=${FILE_PORT} \
     -v /data/zerotier/dist:/app/dist \
     -v /data/zerotier/ztncui:/app/ztncui\
     -v /data/zerotier/one:/var/lib/zerotier-one\
     -v /data/ports:/app/ports\
     xubiaolin/zerotier-planet:latest
}

function menu(){
    echo "欢迎使用zerotier-planet脚本，请选择需要执行的操作："
    echo "1. 安装"
    echo "2. 卸载"
    echo "3. 更新"
    echo "4. 查看信息"
    echo "5. 退出"
    read -p "请输入数字：" num
    case "$num" in
    [1] ) install;;
    [2] ) uninstall;;
    [3] ) update;;
    [4] ) info;;
    [5] ) exit;;
    *) echo "请输入正确数字 [1-5]";;
    esac
}

menu