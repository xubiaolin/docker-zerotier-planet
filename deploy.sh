#!/bin/bash
CONTAINER_NAME=myztplanet

# 如果是centos 且内核版本小于5.*，提示内核版本太低
kernel_check(){
    os_name=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
    kernel_version=$(uname -r | cut -d'.' -f1)
    if [[ "$kernel_version" -lt 5 ]]; then
        echo "内核版本太低,请在菜单中选择内核升级[仅支持centos]"
        exit 1
    else
        echo "系统和内核版本检查通过。"
    fi
}

update_centos_kernal(){
    echo "请注意备份数据，升级内核有风险"
    # 输入y/Y继续
    read -p "是否继续升级内核?(y/n)" continue_update
    continue_update=${continue_update:-n}
    if [[ "$continue_update" =~ ^[Yy]$ ]]; then
        echo "开始升级内核..."
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        rpm -Uvh https://www.elrepo.org/elrepo-release-7.el8.elrepo.noarch.rpm
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        grub2-set-default 0
        echo "内核升级完成，请重启系统"
        exit 0
    else
        echo "已取消升级内核"
        exit 0
    fi

}

install_lsof() {
    if [ ! -f "/usr/bin/lsof" ]; then
        echo "开始安装lsof工具..."
        [ -f "/usr/bin/apt" ] && (
            apt update
            apt install -y lsof
        )
        [ -f "/usr/bin/yum" ] && yum install -y lsof
    fi
}

check_port() {
    local port=$1
    if [ $(lsof -i:${port} | wc -l) -gt 0 ]; then
        echo "端口${port}已被占用，请重新输入"
        exit 1
    fi
}

read_port() {
    local port
    local prompt=$1
    read -p "${prompt}" port
    while [[ ! "$port" =~ ^[0-9]+$ ]]; do
        read -p "端口号必须是数字，请重新输入: " port
    done
    check_port $port
    echo $port
}

install() {
    kernel_check

    echo "开始安装，如果你已经安装了，将会删除旧的数据，10s后开始安装..."
    sleep 10

    install_lsof

    docker rm -f ${CONTAINER_NAME}
    rm -rf $(pwd)/data/zerotier

    ZT_PORT=$(read_port "请输入zerotier-planet要使用的端口号,例如9994: ")
    API_PORT=$(read_port "请输入zerotier-planet的API端口号,例如3443: ")
    FILE_PORT=$(read_port "请输入zerotier-planet的FILE端口号,例如3000: ")

    configure_ip() {
        ipv4=$(curl -s https://ipv4.icanhazip.com/)
        ipv6=$(curl -s https://ipv6.icanhazip.com/)
        echo "获取到的IPv4地址为: $ipv4"
        echo "获取到的IPv6地址为: $ipv6"
    }

    read -p "是否自动获取公网IP地址?(y/n)" use_auto_ip
    use_auto_ip=${use_auto_ip:-y}
    if [[ "$use_auto_ip" =~ ^[Yy]$ ]]; then
        configure_ip

        read -p "是否使用上面获取到的IP地址?(y/n)" use_auto_ip_result
        use_auto_ip_result=${use_auto_ip_result:-y}
        if [[ "$use_auto_ip_result" =~ ^[Nn]$ ]]; then
            read -p "请输入IPv4地址: " ipv4
            read -p "请输入IPv6地址(可留空): " ipv6
        fi
    else
        read -p "请输入IPv4地址: " ipv4
        read -p "请输入IPv6地址(可留空): " ipv6
    fi

    echo "---------------------------"
    echo "使用的端口号为：${ZT_PORT}"
    echo "API端口号为：${API_PORT}"
    echo "FILE端口号为：${FILE_PORT}"
    echo "IPv4地址为：${ipv4}"
    echo "IPv6地址为：${ipv6}"
    echo "---------------------------"

    docker run -d \
        --name ${CONTAINER_NAME} \
        -p ${ZT_PORT}:${ZT_PORT} \
        -p ${ZT_PORT}:${ZT_PORT}/udp \
        -p ${API_PORT}:${API_PORT} \
        -p ${FILE_PORT}:${FILE_PORT} \
        -e IP_ADDR4=${ipv4} \
        -e IP_ADDR6=${ipv6} \
        -e ZT_PORT=${ZT_PORT} \
        -e API_PORT=${API_PORT} \
        -e FILE_SERVER_PORT=${FILE_PORT} \
        -v $(pwd)/data/zerotier/dist:/app/dist \
        -v $(pwd)/data/zerotier/ztncui:/app/ztncui \
        -v $(pwd)/data/zerotier/one:/var/lib/zerotier-one -v $(pwd)/data/zerotier/config:/app/config --restart unless-stopped xubiaolin/zerotier-planet:latest

    if [ $? -ne 0 ]; then
        echo "安装失败"
        exit 1
    fi

    sleep 10

    retrieve_keys() {
        KEY=$(docker exec -it ${CONTAINER_NAME} sh -c 'cat /app/config/file_server.key')
        MOON_NAME=$(docker exec -it ${CONTAINER_NAME} sh -c 'ls /app/dist | grep moon')
    }

    retrieve_keys

    clean_vars() {
        ipv4=$(echo $ipv4 | tr -d '\r')
        FILE_PORT=$(echo $FILE_PORT | tr -d '\r')
        KEY=$(echo $KEY | tr -d '\r')
        MOON_NAME=$(echo $MOON_NAME | tr -d '\r')
    }

    clean_vars

    echo "安装完成"
    echo "---------------------------"
    echo "请访问 http://${ipv4}:${API_PORT} 进行配置"
    echo "默认用户名：admin"
    echo "默认密码：password"
    echo "请及时修改密码"
    echo "---------------------------"

    echo "moon配置和planet配置在 $(pwd)/data/zerotier/dist 目录下"
    echo -e "moons 文件下载： http://${ipv4}:${FILE_PORT}/${MOON_NAME}?key=${KEY} "
    echo -e "planet文件下载： http://${ipv4}:${FILE_PORT}/planet?key=${KEY} "

    echo "---------------------------"
    echo "请放行以下端口请：${ZT_PORT}/tcp,${ZT_PORT}/udp，${API_PORT}/tcp，${FILE_PORT}/tcp"
    echo "---------------------------"
}

info() {
    docker inspect ${CONTAINER_NAME} >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "容器${CONTAINER_NAME}不存在，请先安装"
        exit 1
    fi

    extract_config() {
        local config_name=$1
        docker exec -it ${CONTAINER_NAME} sh -c "cat /app/config/${config_name}" | tr -d '\r'
    }

    ipv4=$(extract_config "ip_addr4")
    ipv6=$(extract_config "ip_addr6")
    API_PORT=$(extract_config "ztncui.port")
    FILE_PORT=$(extract_config "file_server.port")
    ZT_PORT=$(extract_config "zerotier-one.port")
    KEY=$(extract_config "file_server.key")

    MOON_NAME=$(docker exec -it ${CONTAINER_NAME} sh -c "ls /app/dist | grep moon" | tr -d '\r')

    echo "---------------------------"
    echo "以下端口的tcp和udp协议请放行：${ZT_PORT}，${API_PORT}，${FILE_PORT}"
    echo "---------------------------"
    echo "请访问 http://${ipv4}:${API_PORT} 进行配置"
    echo "默认用户名：admin"
    echo "默认密码：password"
    echo "请及时修改密码"
    echo "---------------------------"
    echo "moon配置和planet配置在 $(pwd)/data/zerotier/dist 目录下"
    echo ""
    echo "planet文件下载： http://${ipv4}:${FILE_PORT}/planet?key=${KEY} "
    echo "moon文件下载： http://${ipv4}:${FILE_PORT}/${MOON_NAME}?key=${KEY} "
}

uninstall() {
    echo "开始卸载..."

    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
    docker rmi xubiaolin/zerotier-planet:latest

    read -p "是否删除数据?(y/n)" delete_data
    delete_data=${delete_data:-n}
    if [[ "$delete_data" =~ ^[Yy]$ ]]; then
        rm -rf $(pwd)/data/zerotier
    fi

    echo "卸载完成"
}

# update() {
#     docker inspect ${CONTAINER_NAME} >/dev/null 2>&1
#     if [ $? -ne 0 ]; then
#         echo "容器${CONTAINER_NAME}不存在，请先安装"
#         exit 1
#     fi

#     echo "如果用于生产环境，请先备份数据，不建议直接更新，10s后开始更新..."
#     sleep 10

#     if [ ! -d "$(pwd)/data/zerotier" ]; then
#         echo "目录$(pwd)/data/zerotier不存在，无法更新"
#         exit 0
#     fi

#     extract_config() {
#         local config_name=$1
#         docker exec -it ${CONTAINER_NAME} sh -c "cat /app/config/${config_name}" | tr -d '\r'
#     }

#     ipv4=$(extract_config "ip_addr4")
#     ipv6=$(extract_config "ip_addr6")
#     API_PORT=$(extract_config "ztncui.port")
#     FILE_PORT=$(extract_config "ztncui.port")
#     ZT_PORT=$(extract_config "zerotier-one.port")

#     echo "---------------------------"
#     echo "ipv4地址为：${ipv4}"
#     echo "ipv6地址为：${ipv6}"
#     echo "API端口号为：${API_PORT}"
#     echo "FILE端口号为：${FILE_PORT}"
#     echo "ZT端口号为：${ZT_PORT}"

#     docker stop ${CONTAINER_NAME}
#     docker rm ${CONTAINER_NAME}

#     docker pull xubiaolin/zerotier-planet:latest
#     docker run -d --name ${CONTAINER_NAME} -p ${ZT_PORT}:${ZT_PORT} \
#         -p ${ZT_PORT}:${ZT_PORT}/udp \
#         -p ${API_PORT}:${API_PORT} \
#         -p ${FILE_PORT}:${FILE_PORT} \
#         -e IP_ADDR4=${ipv4} \
#         -e IP_ADDR6=${ipv6} \
#         -e ZT_PORT=${ZT_PORT} \
#         -e API_PORT=${API_PORT} \
#         -e FILE_SERVER_PORT=${FILE_PORT} \
#         -v $(pwd)/data/zerotier/dist:/app/dist \
#         -v $(pwd)/data/zerotier/ztncui:/app/ztncui \
#         -v $(pwd)/data/zerotier/one:/var/lib/zerotier-one \
#         -v $(pwd)/data/zerotier/config:/app/config \
#         --restart unless-stopped \
#         xubiaolin/zerotier-planet:latest
# }

resetpwd() {
    docker exec -it ${CONTAINER_NAME} sh -c 'cp /app/ztncui/src/etc/default.passwd /app/ztncui/src/etc/passwd'
    if [ $? -ne 0 ]; then
        echo "重置密码失败"
        exit 1
    fi

    docker restart ${CONTAINER_NAME}
    if [ $? -ne 0 ]; then
        echo "重启服务失败"
        exit 1
    fi

    echo "--------------------------------"
    echo "重置密码成功"
    echo "当前用户名 admin, 密码为 password"
    echo "--------------------------------"
}

menu() {
    echo "欢迎使用zerotier-planet脚本，请选择需要执行的操作："
    echo "1. 安装"
    echo "2. 卸载"
    # echo "3. 更新"
    echo "4. 查看信息"
    echo "5. 重置密码"
    echo "6. CentOS内核升级"
    echo "0. 退出"
    read -p "请输入数字：" num
    case "$num" in
    [1]) install ;;
    [2]) uninstall ;;
    # [3]) update ;;
    [4]) info ;;
    [5]) resetpwd ;;
    [6]) update_centos_kernal ;;
    [0]) exit ;;
    *) echo "请输入正确数字 [1-5]" ;;
    esac
}

menu
