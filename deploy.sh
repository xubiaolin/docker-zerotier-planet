#!/bin/bash

CONTAINER_NAME="myztplanet"
ZEROTIER_PATH="$(pwd)/data/zerotier"
CONFIG_PATH="${ZEROTIER_PATH}/config"
DIST_PATH="${ZEROTIER_PATH}/dist"
ZTNCUI_PATH="${ZEROTIER_PATH}/ztncui"
DOCKER_IMAGE="xubiaolin/zerotier-planet:latest"

print_message() {
    local message=$1
    local color_code=$2
    echo -e "\033[${color_code}m${message}\033[0m"
}

# 检查内核版本
kernel_check() {
    os_name=$(grep ^ID= /etc/os-release | cut -d'=' -f2 | tr -d '"')
    kernel_version=$(uname -r | cut -d'.' -f1)
    if ((kernel_version < 5)); then
        if [[ "$os_name" == "centos" ]]; then
            print_message "内核版本太低,请在菜单中选择CentOS内核升级" "31"
        else
            print_message "请自行升级系统内核到5.*及其以上版本" "31"
        fi
        exit 1
    else
        print_message "系统和内核版本检查通过，当前内核版本为：$kernel_version" "32"
    fi
}

# 升级CentOS内核
update_centos_kernel() {
    echo "请注意备份数据，升级内核有风险"
    read -p "是否继续升级内核?(y/n) " continue_update
    if [[ "$continue_update" =~ ^[Yy]$ ]]; then
        echo "升级时间较长，请耐心等待！开始升级内核..."
        yum update -y
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
        yum --disablerepo="*" --enablerepo="elrepo-kernel" install -y kernel-lt-devel kernel-lt
        sudo awk -F\' '$1=="menuentry " {print i++ " : " $2}' /etc/grub2.cfg
        grub2-set-default 0
        grub2-mkconfig -o /boot/grub2/grub.cfg
        read -p "内核升级完成，请重启系统，是否立刻重启?(y/n) " reboot
        if [[ "$reboot" =~ ^[Yy]$ ]]; then
            reboot now
        else
            echo "已取消重启"
            exit 0
        fi
    else
        echo "已取消升级内核"
        exit 0
    fi
}

# 安装lsof工具
install_lsof() {
    if ! command -v lsof &>/dev/null; then
        echo "开始安装lsof工具..."
        if command -v apt &>/dev/null; then
            apt update && apt install -y lsof
        elif command -v yum &>/dev/null; then
            yum install -y lsof
        fi
    fi
}

# 检查端口是否被占用
check_port() {
    local port=$1
    if lsof -i:${port} &>/dev/null; then
        echo "端口${port}已被占用，请重新输入"
        exit 1
    fi
}

# 读取端口号
read_port() {
    local port
    local prompt=$1
    while :; do
        read -p "${prompt}" port
        [[ "$port" =~ ^[0-9]+$ ]] && break
        echo "端口号必须是数字，请重新输入: "
    done
    check_port $port
    echo $port
}

# 获取IP地址
configure_ip() {
    ipv4=$(curl -s https://ipv4.icanhazip.com/)
    ipv6=$(curl -s https://ipv6.icanhazip.com/)
    echo "获取到的IPv4地址为: $ipv4"
    echo "获取到的IPv6地址为: $ipv6"
}

# 安装zerotier-planet
install() {
    kernel_check

    if docker inspect ${CONTAINER_NAME} &>/dev/null; then
        echo "容器${CONTAINER_NAME}已经存在"
        read -p "是否更新版本?(y/n) " update_version
        if [[ "$update_version" =~ ^[Yy]$ ]]; then
            upgrade
            exit 0
        fi
    fi

    echo "开始安装，如果你已经安装了，将会删除旧的数据，10秒后开始安装..."
    sleep 10

    install_lsof

    docker rm -f ${CONTAINER_NAME} || true
    rm -rf ${ZEROTIER_PATH}

    ZT_PORT=$(read_port "请输入zerotier-planet要使用的端口号，例如9994: ")
    API_PORT=$(read_port "请输入zerotier-planet的API端口号，例如3443: ")
    FILE_PORT=$(read_port "请输入zerotier-planet的FILE端口号，例如3000: ")

    read -p "是否自动获取公网IP地址?(y/n) " use_auto_ip
    if [[ "$use_auto_ip" =~ ^[Yy]$ ]]; then
        configure_ip
        read -p "是否使用上面获取到的IP地址?(y/n) " use_auto_ip_result
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
        -v ${DIST_PATH}:/app/dist \
        -v ${ZTNCUI_PATH}:/app/ztncui \
        -v ${ZEROTIER_PATH}/one:/var/lib/zerotier-one \
        -v ${CONFIG_PATH}:/app/config \
        --restart unless-stopped \
        ${DOCKER_IMAGE}

    sleep 10

    KEY=$(docker exec -it ${CONTAINER_NAME} sh -c 'cat /app/config/file_server.key' | tr -d '\r')
    MOON_NAME=$(docker exec -it ${CONTAINER_NAME} sh -c 'ls /app/dist | grep moon' | tr -d '\r')

    echo "安装完成"
    echo "---------------------------"
    echo "请访问 http://${ipv4}:${API_PORT} 进行配置"
    echo "默认用户名：admin"
    echo "默认密码：password"
    echo "请及时修改密码"
    echo "---------------------------"
    echo "moon配置和planet配置在 ${DIST_PATH} 目录下"
    echo "moons 文件下载： http://${ipv4}:${FILE_PORT}/${MOON_NAME}?key=${KEY} "
    echo "planet文件下载： http://${ipv4}:${FILE_PORT}/planet?key=${KEY} "
    echo "---------------------------"
    echo "请放行以下端口：${ZT_PORT}/tcp,${ZT_PORT}/udp，${API_PORT}/tcp，${FILE_PORT}/tcp"
    echo "---------------------------"
}

install_from_config() {
    if [ ! -d "${CONFIG_PATH}" ] || [ ! "$(ls -A ${CONFIG_PATH})" ]; then
        echo "配置文件目录不存在或为空，请先上传配置文件"
        exit 1
    fi

    extract_config() {
        local config_name=$1
        cat ${CONFIG_PATH}/${config_name} | tr -d '\r'
    }

    ipv4=$(extract_config "ip_addr4")
    ipv6=$(extract_config "ip_addr6")
    API_PORT=$(extract_config "ztncui.port")
    FILE_PORT=$(extract_config "file_server.port")
    ZT_PORT=$(extract_config "zerotier-one.port")
    KEY=$(extract_config "file_server.key")
    MOON_NAME=$(ls ${DIST_PATH}/ | grep moon | tr -d '\r')

    echo "---------------------------"
    echo "ipv4:${ipv4}"
    echo "ipv6:${ipv6}"
    echo "API_PORT:${API_PORT}"
    echo "FILE_PORT:${FILE_PORT}"
    echo "ZT_PORT:${ZT_PORT}"
    echo "KEY:${KEY}"
    echo "MOON_NAME:${MOON_NAME}"
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
        -v ${DIST_PATH}:/app/dist \
        -v ${ZTNCUI_PATH}:/app/ztncui \
        -v ${ZEROTIER_PATH}/one:/var/lib/zerotier-one \
        -v ${CONFIG_PATH}:/app/config \
        --restart unless-stopped \
        ${DOCKER_IMAGE}
}

upgrade() {
    if ! docker inspect ${CONTAINER_NAME} &>/dev/null; then
        echo "容器${CONTAINER_NAME}不存在，请先安装"
        exit 1
    fi

    docker pull ${DOCKER_IMAGE}
    new_image_id=$(docker inspect ${DOCKER_IMAGE} --format='{{.Id}}')
    old_image_id=$(docker inspect ${CONTAINER_NAME} --format='{{.Image}}')
    if [ "$new_image_id" == "$old_image_id" ]; then
        print_message "当前版本已经是最新版本" "32"
        exit 0
    else
        echo "发现新版本，开始升级...new_image_id:${new_image_id},old_image_id:${old_image_id}"
        echo "更新可能存在风险，请手动备份data目录中的数据,谨慎操作"
        read -p "是否继续升级?(y/n) " continue_upgrade
        if [[ ! "$continue_upgrade" =~ ^[Yy]$ ]]; then
            echo "已取消升级"
            exit 0
        fi
    fi

    echo "开始升级，将会删除旧的容器，10秒后开始升级..."
    sleep 10

    docker rm -f ${CONTAINER_NAME} || true
    install_from_config
}

info() {
    if ! docker inspect ${CONTAINER_NAME} &>/dev/null; then
        echo "容器${CONTAINER_NAME}不存在，请先安装"
        exit 1
    fi

    extract_config() {
        local config_name=$1
        cat ${CONFIG_PATH}/${config_name} | tr -d '\r'
    }

    ipv4=$(extract_config "ip_addr4")
    ipv6=$(extract_config "ip_addr6")
    API_PORT=$(extract_config "ztncui.port")
    FILE_PORT=$(extract_config "file_server.port")
    ZT_PORT=$(extract_config "zerotier-one.port")
    KEY=$(extract_config "file_server.key")
    MOON_NAME=$(ls ${DIST_PATH}/ | grep moon | tr -d '\r')

    echo "---------------------------"
    print_message "以下端口的tcp和udp协议请放行：${ZT_PORT}，${API_PORT}，${FILE_PORT}" "32"
    echo "---------------------------"
    echo "请访问 http://${ipv4}:${API_PORT} 进行配置"
    echo "默认用户名：admin"
    echo "默认密码：password"
    echo "请及时修改密码"
    echo "---------------------------"
    print_message "moon配置和planet配置在 ${DIST_PATH} 目录下" "32"
    print_message "planet文件下载： http://${ipv4}:${FILE_PORT}/planet?key=${KEY} " "32"
    print_message "moon文件下载： http://${ipv4}:${FILE_PORT}/${MOON_NAME}?key=${KEY} " "32"
}

uninstall() {
    echo "开始卸载..."

    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
    docker rmi ${DOCKER_IMAGE}

    read -p "是否删除数据?(y/n) " delete_data
    if [[ "$delete_data" =~ ^[Yy]$ ]]; then
        rm -rf ${ZEROTIER_PATH}
    fi

    echo "卸载完成"
}

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
    echo "3. 更新"
    echo "4. 查看信息"
    echo "5. 重置密码"
    echo "6. CentOS内核升级"
    echo "0. 退出"
    read -p "请输入数字：" num
    case "$num" in
    1) install ;;
    2) uninstall ;;
    3) upgrade ;;
    4) info ;;
    5) resetpwd ;;
    6) update_centos_kernel ;;
    0) exit ;;
    *) echo "请输入正确数字 [0-6]" ;;
    esac
}

menu
