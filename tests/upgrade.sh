#!/usr/bin/env bash
# 用一次性 Docker 容器检验升级事务，包括进程被 SIGKILL 后的恢复。
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
source "$repo/deploy.sh"

work=$(mktemp -d)
CONTAINER_NAME="zt-upgrade-test-${work##*.}"
layout_test=${TEST_UPGRADE_LAYOUT:-directory}
ZEROTIER_PATH="$work/old deployment"
test_mounts=()
if [[ $layout_test == parent-link ]]; then
    mkdir "$work/disk"
    ln -s "$work/disk" "$work/linked parent"
    ZEROTIER_PATH="$work/linked parent/old deployment"
fi
CONFIG_PATH="$ZEROTIER_PATH/config"
DIST_PATH="$ZEROTIER_PATH/dist"
ZTNCUI_PATH="$ZEROTIER_PATH/ztncui"
base=${TEST_BASE_IMAGE:-alpine:3.22}
tag="zt-transaction-test:${work##*.}"
cleanup() {
    local id
    while read -r id; do
        [[ -z $id ]] || docker rm -fv "$id" >/dev/null
    done < <(docker ps -aq --filter "label=test-instance=$CONTAINER_NAME")
    local path
    for path in "${test_mounts[@]}"; do command sudo -n umount "$path" || return 1; done
    docker image rm "$tag" >/dev/null 2>&1 || true
    docker run --rm --network none -v "$work:/test-data" --entrypoint sh "$base" \
        -c 'rm -rf /test-data/*' >/dev/null
    rmdir "$work"
}
trap cleanup EXIT
mkdir "$work/build"
cp "$repo/patch/settings.js" "$work/build/"
docker build -q -t "$tag" -f - "$work/build" <<BUILD >/dev/null
FROM node:22-bookworm-slim
COPY settings.js /app/settings.js
LABEL test-instance=$CONTAINER_NAME org.zerotier-planet.retry-safe=1 org.zerotier-planet.secure-admin=1
BUILD
DOCKER_IMAGE=$(docker image inspect --format '{{.Id}}' "$tag")
case $layout_test in
    root-link)
        mkdir "$work/disk"
        ln -s "$work/disk" "$ZEROTIER_PATH"
        ;;
    mounts)
        mkdir "$ZEROTIER_PATH"
        command sudo -n mount -t tmpfs -o size=8m tmpfs "$ZEROTIER_PATH"
        test_mounts=("$ZEROTIER_PATH")
        command sudo -n mkdir "$ZEROTIER_PATH/one"
        command sudo -n mount -t tmpfs -o size=8m tmpfs "$ZEROTIER_PATH/one"
        test_mounts=("$ZEROTIER_PATH/one" "$ZEROTIER_PATH")
        ;;
esac
mkdir -p "$ZEROTIER_PATH"/{config,dist,ztncui,one}
old_inode=$(stat -c "%d:%i" "$ZEROTIER_PATH")
fixture_mounts=(-v "$CONFIG_PATH:/app/config" -v "$DIST_PATH:/app/dist"
        -v "$ZTNCUI_PATH:/app/ztncui" -v "$ZEROTIER_PATH/one:/var/lib/zerotier-one")
read -r zt_host api_host files_host < <(python3 - <<'PY'
import socket
sockets = [socket.socket() for _ in range(3)]
for listener in sockets:
    listener.bind(('127.0.0.1', 0))
print(*(listener.getsockname()[1] for listener in sockets))
PY
)
old=$(docker run -d --name "$CONTAINER_NAME" --restart always --label "test-instance=$CONTAINER_NAME" \
    -p "$zt_host:9994/tcp" -p "$zt_host:9994/udp" \
    -p "127.0.0.1:$api_host:3443/tcp" -p "127.0.0.1:$files_host:3000/tcp" \
    "${fixture_mounts[@]}" --entrypoint sh "$base" -c 'trap "exit 0" TERM; while :; do sleep 1; done')
original_bindings=$(port_bindings "$old" NetworkSettings.Ports)
docker exec "$old" sh -ec '
    echo previous > /var/lib/zerotier-one/.identity
    chmod 0600 /var/lib/zerotier-one/.identity
    echo 9994 > /app/config/zerotier-one.port
    echo 3443 > /app/config/ztncui.port
    echo 3000 > /app/config/file_server.port
    echo 192.0.2.1 > /app/config/ip_addr4
    touch /app/config/ip_addr6'
# 即使本机 sudo 可用，测试也覆盖只持有 docker 组权限的普通用户。
sudo() { return 1; }
run_container() {
    local image=$1
    shift
    [[ $(docker inspect --format '{{.State.Running}} {{.HostConfig.RestartPolicy.Name}}' "$old") == "false no" ]] || return 1
    docker run -d --name "$CONTAINER_NAME" --label "org.zerotier-planet.upgrade=$UPGRADE_TOKEN" \
        --label "test-instance=$CONTAINER_NAME" "${fixture_mounts[@]}" "$@" --entrypoint sleep "$image" 3600 >/dev/null
    docker exec "$CONTAINER_NAME" sh -ec '
        test "$(cat /var/lib/zerotier-one/.identity)" = previous
        echo candidate > /var/lib/zerotier-one/.identity
        touch /app/dist/candidate-only'
}
wait_ready() {
    if [[ $(docker inspect --format '{{.Id}}' "$1") == "$old" ]]; then
        if [[ ${old_unhealthy:-false} == true ]]; then
            touch "$work/old-readiness-checked"
            return 1
        fi
        [[ $(docker inspect --format '{{.State.Running}}' "$1") == true ]]
        return
    fi
    case "$outcome" in
        crash) kill -KILL "$BASHPID" ;;
        unhealthy) return 1 ;;
        healthy) return 0 ;;
    esac
}
assert_original() {
    [[ $(stat -c "%d:%i" "$ZEROTIER_PATH") == "$old_inode" ]]
    [[ $(docker inspect --format '{{.Id}} {{.State.Running}} {{.HostConfig.RestartPolicy.Name}}' "$CONTAINER_NAME") == "$old true always" ]]
    docker exec "$old" sh -ec '
        test "$(cat /var/lib/zerotier-one/.identity)" = previous
        test "$(stat -c "%a %u" /var/lib/zerotier-one/.identity)" = "600 0"
        test ! -e /app/dist/incomplete-restore
        test ! -e /app/dist/candidate-only'
    [[ ! -e $ZEROTIER_PATH.upgrade ]]
}
# 预检失败时旧服务持续在线，同一容器没有重启。
started=$(docker inspect --format '{{.State.StartedAt}}' "$old")
legacy_id=$(docker inspect --format '{{.Image}}' "$old")
if DOCKER_IMAGE="$legacy_id" upgrade <<< y; then exit 1; fi
if ( load_config() { return 1; }; upgrade <<< y ); then exit 1; fi
[[ $(docker inspect --format '{{.State.StartedAt}}' "$old") == "$started" ]]
assert_original
if [[ $layout_test == mounts ]]; then
    mkdir -p "$work/overlapping/child"
    command sudo -n mount --bind "$work/overlapping" "$DIST_PATH"
    command sudo -n mount --bind "$work/overlapping/child" "$CONFIG_PATH"
    test_mounts=("$CONFIG_PATH" "$DIST_PATH" "${test_mounts[@]}")
    if upgrade_layout; then exit 1; fi
    if verify_mounts "$CONTAINER_NAME"; then exit 1; fi
    command sudo -n umount "$CONFIG_PATH"
    command sudo -n umount "$DIST_PATH"
    test_mounts=("${test_mounts[@]:2}")
    mkdir -p "$work/fresh"/{config,dist,one,ztncui,lost+found}
    touch "$work/fresh/.install-settings"
    ZEROTIER_PATH="$work/fresh" pending_installation "$DOCKER_IMAGE"
fi
upgrade <<< n
assert_original
outcome=unhealthy
if upgrade <<< y; then exit 1; fi
assert_original
# 原容器仍无法就绪时，回滚完成后应允许菜单继续执行。
old_unhealthy=true
if upgrade <<< y; then exit 1; fi
assert_original
[[ -e $work/old-readiness-checked ]]
rm "$work/old-readiness-checked"
unset old_unhealthy
outcome=crash
if { upgrade <<< y; } 2>"$work/intentional-crash.log"; then exit 1; fi
[[ -d $ZEROTIER_PATH.upgrade/data ]]
if [[ $layout_test == mounts ]]; then
    # 遮盖原挂载，验证回滚不会写入刚挂来的其他卷。
    mkdir "$work/unrelated"
    touch "$work/unrelated/keep"
    command sudo -n mount --bind "$work/unrelated" "$ZEROTIER_PATH/one"
    test_mounts=("$ZEROTIER_PATH/one" "${test_mounts[@]}")
    if recover_upgrade; then exit 1; fi
    [[ -e $work/unrelated/keep && ! -e $work/unrelated/.identity ]]
    command sudo -n umount "$ZEROTIER_PATH/one"
    test_mounts=("${test_mounts[@]:1}")
fi
if [[ -e $ZEROTIER_PATH.upgrade/layout ]]; then
    # 模拟还原过程中中断，下一次重试必须重新恢复全部四个目录。
    if ( upgrade_mounted_data() {
        docker run --rm -v "$DIST_PATH:/dist" --entrypoint sh "$base" -c 'touch /dist/incomplete-restore'
        return 1
    }; recover_upgrade ); then exit 1; fi
    [[ $(docker inspect --format '{{.State.Running}}' "$old") == false ]]
fi
recover_upgrade
assert_original

# 半成品原本未就绪，修复失败时只还原其原有状态。强制中断验证标记能够跨进程读取。
outcome=crash
old_unhealthy=true
if { upgrade repair </dev/null; } 2>"$work/repair-crash.log"; then exit 1; fi
[[ -d $ZEROTIER_PATH.upgrade/data ]]
recover_upgrade
assert_original
[[ ! -e $work/old-readiness-checked ]]
unset old_unhealthy
# 已停止的半成品应保持停止。
save_launch_settings "$CONTAINER_NAME"
docker stop "$old" >/dev/null
outcome=unhealthy
if upgrade repair </dev/null; then exit 1; fi
[[ $(docker inspect --format '{{.State.Running}} {{.HostConfig.RestartPolicy.Name}}' "$old") == "false always" ]]
[[ ! -e $ZEROTIER_PATH.upgrade ]]
docker start "$old" >/dev/null
assert_original

# 中途备份出错时原数据树仍在原处。
outcome=healthy
if (
    eval "$(declare -f upgrade_fs | sed '1s/upgrade_fs/normal_fs/')"
    upgrade_fs() {
        if [[ $1 == cp ]]; then return 1; fi
        normal_fs "$@"
    }
    upgrade_mounted_data() { return 1; }
    upgrade <<< y
); then exit 1; fi
assert_original
if [[ $layout_test == directory ]]; then
    # 提交后候选容器丢失，恢复应保留已提交的数据和端口信息。
    if (
        initial_password_hint() { kill -KILL "$BASHPID"; }
        upgrade <<< y
    ) 2>"$work/commit-crash.log"; then exit 1; fi
    [[ -e $ZEROTIER_PATH.upgrade/committed ]]
    docker rm -f "$CONTAINER_NAME" >/dev/null
    recover_upgrade
    [[ ! -e $ZEROTIER_PATH.upgrade ]]
    [[ -f $DIST_PATH/candidate-only ]]
    load_config
    declare -a recovered_args=()
    recovered_bindings=
    restore_launch_settings "$DOCKER_IMAGE" recovered_args recovered_bindings
    [[ $recovered_bindings == "$original_bindings" ]]
    docker run -d --name "$CONTAINER_NAME" --label "test-instance=$CONTAINER_NAME" \
        "${fixture_mounts[@]}" "${recovered_args[@]}" --entrypoint sleep "$DOCKER_IMAGE" 3600 >/dev/null
else
    upgrade <<< y
fi
[[ $(port_bindings "$CONTAINER_NAME" NetworkSettings.Ports) == "$original_bindings" ]]
[[ $(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER_NAME") == always ]]
docker exec "$CONTAINER_NAME" sh -ec '
    test "$(cat /var/lib/zerotier-one/.identity)" = candidate
    test -e /app/dist/candidate-only'
archives=("$ZEROTIER_PATH".backup.*/)
[[ ${#archives[@]} == 1 && $(stat -c %a "${archives[0]}") == 700 ]]
docker run --rm --network none -v "${archives[0]}data:/saved:ro" --entrypoint sh "$base" -ec '
    test "$(cat /saved/one/.identity)" = previous
    test "$(stat -c "%a %u" /saved/one/.identity)" = "600 0"
    test ! -e /saved/dist/candidate-only'
upgrade </dev/null
uninstall <<< y
case $layout_test in
    root-link|mounts)
        [[ $(stat -c "%d:%i" "$ZEROTIER_PATH") == "$old_inode" ]]
        for dir in config dist one ztncui; do
            [[ -d $ZEROTIER_PATH/$dir && -z $(ls -A -- "$ZEROTIER_PATH/$dir") ]]
        done
        ;;
    *) [[ ! -e $ZEROTIER_PATH ]] ;;
esac
[[ -d ${archives[0]} ]]
echo "升级、预检、失败回滚、中断恢复、半成品修复回滚和卸载均已验证。"
