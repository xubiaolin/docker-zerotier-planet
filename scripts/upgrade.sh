# 由 deploy.sh 在持有部署锁的情况下调用。
# 容器可能以 root 写入 0600 的节点身份。使用本机权限或原镜像复制，保留所有者和权限。
upgrade_fs() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
        sudo -n -- "$@"
    else
        local parent=${ZEROTIER_PATH%/*} program=$1
        shift
        if [[ $program == cp ]]; then
            # 空间耗尽时就在现有 helper 中释放未完成的副本。
            program=sh
            set -- -c 'cp "$@" || { rm -rf "$3"; exit 1; }' copy "$@"
        fi
        docker run --rm --network none --user 0 \
            --label "org.zerotier-planet.upgrade-fs=$ZEROTIER_PATH" \
            -v "$parent:$parent" --entrypoint "$program" "$fs_image" "$@"
    fi
}

# 旧版 BusyBox mv 没有 -T。每个目的名都必须为空，部署锁串行化每次重命名。
upgrade_move() {
    [[ ! -e $2 && ! -L $2 ]] || return 1
    upgrade_fs mv "$1" "$2"
}

# 普通目录可以重命名。独立挂载和数据根软链接必须保留原路径和挂载点。
upgrade_layout() {
    local root parent target mounts dir ancestor kind=rename
    root=$(realpath -e -- "$ZEROTIER_PATH") && parent=$(realpath -e -- "${ZEROTIER_PATH%/*}") || return 1
    [[ ! -L $ZEROTIER_PATH ]] || kind=mounted
    for dir in "$root" "$root"/{config,dist,one,ztncui}; do
        [[ -d $dir && ! -L $dir ]] || { echo "需要数据目录 $dir；外部子目录请使用 bind mount。" >&2; return 1; }
        # 包括 bind 到 / 或备份目录祖先的情况，防止备份复制自己或还原到系统目录。
        ancestor=$parent
        while [[ ! $ancestor -ef "$dir" ]]; do
            [[ $ancestor != / ]] || break
            ancestor=${ancestor%/*}
            ancestor=${ancestor:-/}
        done
        if [[ $ancestor -ef "$dir" ]]; then echo "数据目录 $dir 与备份路径重叠。" >&2; return 1; fi
    done
    mounts=$(findmnt -rn -o TARGET) || return 1
    while IFS= read -r target; do
        printf -v target '%b' "$target"
        case "$target" in
            "$root"|"$root/config"|"$root/dist"|"$root/one"|"$root/ztncui") kind=mounted ;;
            "$root/"*) echo "数据目录内部还有挂载点 $target，请将磁盘挂载到数据根或四个持久化目录。" >&2; return 1 ;;
        esac
    done <<< "$mounts"
    printf '%s\n' "$kind"
    stat -Lc '%d:%i' -- "$root" "$root"/{config,dist,one,ztncui}
}

# 快照始终在单独的私有目录中。恢复只挂载容器可写的四个目录，并逐一同步到磁盘。
upgrade_mounted_data() {
    local action=$1 dir
    local -a mounts=(-v "$journal:/private:ro")
    if [[ $action == backup ]]; then
        docker run --rm --network none --user 0 --label "org.zerotier-planet.upgrade-fs=$ZEROTIER_PATH" \
            -v "$journal:/private" -v "$ZEROTIER_PATH:/live:ro" --entrypoint sh "$fs_image" -ec '
                ids=$(stat -c "%d:%i" /live /live/config /live/dist /live/one /live/ztncui)
                test "$ids" = "$(tail -n +2 /private/layout)"
                cp -a /live /private/next || { rm -rf /private/next; exit 1; }'
    else
        for dir in config dist one ztncui; do mounts+=(-v "$ZEROTIER_PATH/$dir:/live/$dir"); done
        docker run --rm --network none --user 0 --label "org.zerotier-planet.upgrade-fs=$ZEROTIER_PATH" \
            "${mounts[@]}" --entrypoint sh "$fs_image" -ec '
                ids=$(stat -c "%d:%i" /live/config /live/dist /live/one /live/ztncui)
                test "$ids" = "$(tail -n +3 /private/layout)"
                for dir in config dist one ztncui; do
                    test -d "/private/data/$dir" && test ! -L "/private/data/$dir" || exit 1
                    cd "/live/$dir"
                    for entry in .[!.]* ..?* *; do
                        if [ -e "$entry" ] || [ -L "$entry" ]; then rm -rf -- "$entry"; fi
                    done
                    cp -a "/private/data/$dir/." .
                done
                sync'
    fi
}

# 输出为空时容器确实不存在。守护进程通讯错误会以非零状态返回。
upgrade_container_id() {
    docker container ls --all --quiet --no-trunc --filter "$1"
}

recover_upgrade() (
    local journal="${ZEROTIER_PATH}.upgrade" old fs_image policy was_running token
    local current candidate helper old_name archive discarded layout
    [[ -e $journal || -L $journal ]] || return 0
    if [[ -L $journal || ! -f $journal/state ]] ||
        ! read -r old fs_image policy was_running token < "$journal/state" ||
        [[ ! $old =~ ^[a-f0-9]{64}$ || ! $fs_image =~ ^sha256:[a-f0-9]{64}$ ||
           ! $policy =~ ^(no|always|unless-stopped|on-failure(:[0-9]+)?)$ ||
           ! $was_running =~ ^(true|false)$ || ! $token =~ ^[a-zA-Z0-9]{8}$ ]]; then
        echo "无法读取升级记录，请检查 $journal/state" >&2
        return 1
    fi

    # Docker 客户端被强制结束后，守护进程中的文件复制可能还在运行。
    helper=$(upgrade_container_id "label=org.zerotier-planet.upgrade-fs=$ZEROTIER_PATH") || return 1
    if [[ -n $helper ]]; then
        docker wait "$helper" >/dev/null 2>&1 || {
            helper=$(upgrade_container_id "label=org.zerotier-planet.upgrade-fs=$ZEROTIER_PATH") || return 1
            [[ -z $helper ]] || return 1
        }
    fi
    candidate=$(upgrade_container_id "label=org.zerotier-planet.upgrade=$token") || return 1
    current=$(upgrade_container_id "name=^/${CONTAINER_NAME}$") || return 1
    if [[ -n $candidate && $candidate != "$current" ]] ||
        [[ -n $current && $current != "$old" && $current != "$candidate" ]]; then
        echo "容器名 $CONTAINER_NAME 已由其他容器占用，升级记录保存在 $journal" >&2
        return 1
    fi

    if [[ -f $journal/committed ]]; then
        [[ -n $candidate && $current == "$candidate" && -d $journal/data ]] || return 1
        archive="${ZEROTIER_PATH}.backup.$token"
        [[ ! -e $archive && ! -L $archive ]] || return 1
        current=$(upgrade_container_id "id=$old") || return 1
        if [[ -n $current ]]; then docker rm "$old" >/dev/null || return 1; fi
        upgrade_move "$journal" "$archive" || return 1
        sync -f "${ZEROTIER_PATH%/*}" || return 1
        echo "升级完成，升级前的数据保存在 $archive/data"
        return 0
    fi

    echo "正在恢复升级前的容器和数据……" >&2
    old_name=$(docker container inspect --format '{{.Name}}' "$old") || return 1
    if [[ -n $candidate ]]; then docker rm -f "$candidate" >/dev/null || return 1; fi
    # 仅 data 存在时原目录才已经搬走。任何一步中断都可根据目录重试。
    if [[ -f $journal/layout ]]; then
        layout=$(upgrade_layout) || return 1
        if [[ $layout != "$(<"$journal/layout")" ]]; then
            echo "数据挂载已改变，请恢复升级前的挂载后重试。" >&2
            return 1
        fi
        if [[ -d $journal/data && ! -f $journal/restored ]]; then
            upgrade_mounted_data restore || return 1
            touch "$journal/restored" && sync -f "$journal" || return 1
        fi
    elif [[ -d $journal/data ]]; then
        if [[ -e $ZEROTIER_PATH ]]; then
            upgrade_move "$ZEROTIER_PATH" "$journal/failed" || return 1
        fi
        upgrade_move "$journal/data" "$ZEROTIER_PATH" || return 1
        sync -f "$journal" || return 1
    fi
    # 尽早释放复制占用的空间，包括 ENOSPC 时未完成的副本。
    upgrade_fs rm -rf "$journal/next" "$journal/failed" || return 1
    if [[ $old_name != "/$CONTAINER_NAME" ]]; then
        docker rename "$old" "$CONTAINER_NAME" || return 1
    fi
    if [[ $was_running == true ]]; then
        docker start "$old" >/dev/null || return 1
    fi
    docker update --restart="$policy" "$old" >/dev/null || return 1
    if [[ $was_running == true && ! -f $journal/repair ]]; then
        wait_ready "$CONTAINER_NAME" || return 1
    fi
    discarded="${ZEROTIER_PATH}.rollback.$token"
    upgrade_move "$journal" "$discarded" || return 1
    sync -f "${ZEROTIER_PATH%/*}" || return 1
    upgrade_fs rm -rf "$discarded" || return 1
    echo "已恢复升级前的容器和数据。" >&2
)

upgrade() (
    local journal="${ZEROTIER_PATH}.upgrade" old fs_image policy retries running new_image
    local info confirm staging token UPGRADE_TOKEN layout mode=${1:-upgrade}
    recover_upgrade || return 1
    info=$(docker container inspect --format '{{.Id}} {{.Image}} {{.HostConfig.RestartPolicy.Name}} {{.HostConfig.RestartPolicy.MaximumRetryCount}} {{.State.Running}}' "$CONTAINER_NAME") || return 1
    read -r old fs_image policy retries running <<< "$info"
    new_image=$(resolve_image "$DOCKER_IMAGE" refresh) || return 1
    if [[ ! $new_image =~ ^sha256:[0-9a-f]{64}$ ]]; then
        echo "无法确定候选镜像 ID：$DOCKER_IMAGE" >&2
        return 1
    fi
    if [[ $mode != repair && $new_image == "$fs_image" ]]; then
        echo "当前版本已经是最新版本"
        return 0
    fi
    verify_mounts "$CONTAINER_NAME" || return 1
    if [[ $mode == repair ]]; then
        load_repair_config "$new_image" || { echo "无法读取修复所需的部署参数。" >&2; return 1; }
    else
        load_config || { echo "无法读取现有部署的端口和地址。" >&2; return 1; }
    fi
    layout=$(upgrade_layout) || return 1
    if [[ $mode == repair ]]; then
        echo "将备份现有数据并重建未就绪的容器。"
    else
        echo "发现新版本。将停止容器，备份完整数据并验证新版本。"
        read -r -p "是否继续升级?(y/n) " confirm || return 1
        if [[ ! $confirm =~ ^[Yy]$ ]]; then echo "已取消升级"; return 0; fi
    fi
    staging=$(upgrade_fs mktemp -d "${ZEROTIER_PATH}.prepare.XXXXXXXX") || return 1
    token=${staging##*.}
    UPGRADE_TOKEN=$token
    trap 'upgrade_fs rm -rf "$staging"' EXIT
    upgrade_fs chown "$(id -u):$(id -g)" "$staging" || return 1
    if [[ $layout == mounted$'\n'* ]]; then printf '%s\n' "$layout" > "$staging/layout" || return 1; fi
    if [[ $mode == repair ]]; then touch "$staging/repair" || return 1; fi
    if [[ $policy == on-failure && $retries != 0 ]]; then policy="on-failure:$retries"; fi
    printf '%s %s %s %s %s\n' "$old" "$fs_image" "$policy" "$running" "$token" > "$staging/state" || return 1
    sync -f "$staging" || return 1
    upgrade_move "$staging" "$journal" || return 1
    trap 'result=$?; trap - EXIT; recover_upgrade || exit 1; exit "$result"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    sync -f "$journal" || return 1

    docker update --restart=no "$old" >/dev/null || return 1
    docker stop "$old" >/dev/null || return 1
    if [[ -f $journal/layout ]]; then
        upgrade_mounted_data backup || return 1
    else
        upgrade_fs cp -a "$ZEROTIER_PATH" "$journal/next" || return 1
    fi
    sync -f "$journal" || return 1
    docker rename "$old" "${CONTAINER_NAME}.old.$token" || return 1
    if [[ -f $journal/layout ]]; then
        [[ $(upgrade_layout) == "$layout" ]] || return 1
        upgrade_move "$journal/next" "$journal/data" || return 1
    else
        upgrade_move "$ZEROTIER_PATH" "$journal/data" || return 1
        sync -f "$journal" || return 1
        upgrade_move "$journal/next" "$ZEROTIER_PATH" || return 1
    fi
    sync -f "$journal" || return 1
    run_container "$new_image" || return 1
    wait_ready "$CONTAINER_NAME" || return 1
    touch "$journal/committed" || return 1
    sync -f "$journal"
)
