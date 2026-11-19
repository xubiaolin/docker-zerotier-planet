#!/bin/bash

CONTAINER_NAME=${CONTAINER_NAME:-myztplanet}
ZEROTIER_PATH="$(pwd -P)/data/zerotier"
CONFIG_PATH="${ZEROTIER_PATH}/config"
DIST_PATH="${ZEROTIER_PATH}/dist"
ZTNCUI_PATH="${ZEROTIER_PATH}/ztncui"
IMAGE_EXPLICIT=${DOCKER_IMAGE:+1}
DOCKER_IMAGE=${DOCKER_IMAGE:-xubiaolin/zerotier-planet:latest}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$SCRIPT_DIR/scripts/deployment.sh"
source "$SCRIPT_DIR/scripts/upgrade.sh"

check_proxy() {
    if [[ -f /etc/docker/daemon.json ]] && grep -q proxy /etc/docker/daemon.json; then
        echo "daemon.json 中有代理配置。"
    else
        echo "daemon.json 中未发现代理配置。"
    fi
    echo "部署镜像：$DOCKER_IMAGE"
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

uninstall() {
    echo "开始卸载..."

    local image
    verify_mounts "$CONTAINER_NAME" || return 1
    image=$(docker inspect --format '{{.Config.Image}}' "$CONTAINER_NAME") || return 1
    docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME" || return 1
    docker rmi "$image" || echo "镜像仍保留在本机。"

    read -p "是否删除数据?(y/n) " delete_data
    if [[ "$delete_data" =~ ^[Yy]$ ]]; then
        rm -rf -- "${ZEROTIER_PATH:?}" || return 1
    fi

    echo "卸载完成"
}

resetpwd() {
    verify_mounts "$CONTAINER_NAME" || return 1
    docker exec "$CONTAINER_NAME" sh -c 'cp /app/ztncui/src/etc/default.passwd /app/ztncui/src/etc/passwd'
    if [ $? -ne 0 ]; then
        echo "重置密码失败"
        exit 1
    fi

    docker restart "$CONTAINER_NAME"
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
    echo "1. 安装或重装（保留已有数据）"
    echo "2. 卸载"
    echo "3. 更新"
    echo "4. 查看信息"
    echo "5. 重置密码"
    echo "6. CentOS内核升级"
    echo "7. 检查是否设置代理"
    echo "0. 退出"
    read -r -p "请输入数字：" num || return 1
    case "$num" in
    [1-5])
        docker info >/dev/null || return 1
        exec 9<. || return 1
        command -v flock >/dev/null || { echo "缺少 Linux 的 flock 命令（util-linux）。" >&2; return 1; }
        flock -n 9 || { echo "当前目录已有部署操作正在运行。" >&2; return 1; }
        recover_upgrade || return 1
        ;;
    esac
    case "$num" in
    1) install ;;
    2) uninstall ;;
    3) upgrade ;;
    4) info ;;
    5) resetpwd ;;
    6) update_centos_kernel ;;
    7) check_proxy ;;
    0) exit ;;
    *) echo "请输入正确数字 [0-7]" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    menu
fi
