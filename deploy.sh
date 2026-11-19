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
uninstall() {
    local image fs_image delete_data layout
    verify_mounts "$CONTAINER_NAME" || return 1
    image=$(docker inspect --format '{{.Config.Image}}' "$CONTAINER_NAME") || return 1
    read -r -p "是否删除当前部署目录 $ZEROTIER_PATH 中的数据？(y/n) " delete_data || return 1
    if [[ $delete_data == [Yy] ]]; then
        layout=$(upgrade_layout) || return 1
        fs_image=$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME") || return 1
    fi
    docker stop "$CONTAINER_NAME" || return 1
    if [[ $delete_data == [Yy] ]]; then
        if [[ $(upgrade_layout) != "$layout" ]]; then
            echo "数据挂载已改变，请恢复原挂载后重试。" >&2
            return 1
        fi
        if [[ $layout == mounted$'\n'* ]]; then
            docker run --rm --network none --user 0 -v "$ZEROTIER_PATH:/live" --entrypoint sh "$fs_image" -ec '
                ids=$(stat -c "%d:%i" /live /live/config /live/dist /live/one /live/ztncui)
                test "$ids" = "$1"
                for dir in config dist one ztncui; do
                    find "/live/$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
                done
                rm -f -- /live/.install-settings' delete "${layout#*$'\n'}" || return 1
        else
            upgrade_fs rm -rf -- "${ZEROTIER_PATH:?}" || return 1
        fi
    fi
    docker rm "$CONTAINER_NAME" || return 1
    docker rmi "$image" || echo "镜像仍保留在本机。"
    echo "卸载完成"
}

resetpwd() {
    local secure_admin password
    verify_mounts "$CONTAINER_NAME" || return 1
    secure_admin=$(docker inspect --format '{{index .Config.Labels "org.zerotier-planet.secure-admin"}}' "$CONTAINER_NAME") || return 1
    if [[ $secure_admin != 1 ]]; then
        echo "请先升级容器，再使用随机密码重置。" >&2
        return 1
    fi
    password=$(docker exec "$CONTAINER_NAME" node /app/admin-password.js reset) || return 1
    [[ -n $password ]] || return 1
    printf '管理员 admin 的新密码：%s\n' "$password"
    docker restart "$CONTAINER_NAME" && wait_ready "$CONTAINER_NAME"
}

menu() {
    echo "欢迎使用zerotier-planet脚本，请选择需要执行的操作："
    echo "1. 安装或重装（保留已有数据）"
    echo "2. 卸载"
    echo "3. 更新"
    echo "4. 查看信息"
    echo "5. 重置密码"
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
    7) check_proxy ;;
    0) exit ;;
    *) echo "请输入 0、1、2、3、4、5 或 7。" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    menu
fi
