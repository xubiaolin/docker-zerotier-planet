# Host-side operations shared by installation, recovery and upgrades.

container_exists() {
    docker container inspect "$1" >/dev/null 2>&1
}

verify_mounts() {
    local name=$1 dest type writable source expected mounts count=0
    mounts=$(docker inspect --format '{{range .Mounts}}{{println .Destination .Type .RW .Source}}{{end}}' "$name") || return 1
    while read -r dest type writable source; do
        case "$dest" in
            /app/config) expected=$CONFIG_PATH ;;
            /app/dist) expected=$DIST_PATH ;;
            /app/ztncui) expected=$ZTNCUI_PATH ;;
            /var/lib/zerotier-one) expected=$ZEROTIER_PATH/one ;;
            *) continue ;;
        esac
        if [[ $type != bind || $writable != true || ! "$source" -ef "$expected" ]]; then
            echo "容器 $name 的 $dest 不属于当前部署，请从原项目目录运行。" >&2
            return 1
        fi
        ((count+=1))
    done <<< "$mounts"
    [[ $count == 4 ]] || { echo "容器的四个数据挂载不完整，请检查原部署。" >&2; return 1; }
}

read_config() {
    local filename=$1 value
    if [[ -r "$CONFIG_PATH/$filename" ]]; then
        value=$(cat -- "$CONFIG_PATH/$filename") || return 1
    else
        value=$(docker exec "$CONTAINER_NAME" cat "/app/config/$filename" 2>/dev/null) || return 1
    fi
    printf '%s' "${value%$'\r'}"
}

valid_port() {
    [[ $1 =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_ports() {
    valid_port "$ZT_PORT" && valid_port "$API_PORT" && valid_port "$FILE_PORT" &&
        (( 10#$ZT_PORT != 10#$API_PORT && 10#$ZT_PORT != 10#$FILE_PORT && 10#$API_PORT != 10#$FILE_PORT ))
}

load_config() {
    ZT_PORT=$(read_config zerotier-one.port) && API_PORT=$(read_config ztncui.port) &&
        FILE_PORT=$(read_config file_server.port) || return 1
    ipv4=$(read_config ip_addr4) || ipv4=
    ipv6=$(read_config ip_addr6) || ipv6=
    valid_ports && [[ -n $ipv4 || -n $ipv6 ]]
}

prompt_port() {
    local prompt=$1 port
    while read -r -p "$prompt" port; do
        if valid_port "$port"; then
            printf '%d' "$((10#$port))"
            return 0
        fi
        echo "请输入 1 到 65535 之间的端口。" >&2
    done
    return 1
}

# Read the same legacy configuration sources as the container initializer.
# The read-only root mount also works with root-owned state and a missing container.
probe_settings() {
    local image=$1 output
    shift
    local -a mount_args=() values=()
    if [[ -d $ZEROTIER_PATH ]]; then mount_args=(-v "$ZEROTIER_PATH:/saved:ro"); fi
    output=$(docker run --rm --network none "${mount_args[@]}" -e DEPLOYMENT_DATA=/saved "$@" \
        --entrypoint node "$image" /app/settings.js) || return 1
    mapfile -t values <<< "$output"
    ZT_PORT=${values[0]:-} API_PORT=${values[1]:-} FILE_PORT=${values[2]:-}
    ipv4=${values[3]:-} ipv6=${values[4]:-}
}

load_repair_config() {
    local image=$1 env_line environment
    local -a arguments=()
    environment=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME") || return 1
    while IFS= read -r env_line; do
        case "$env_line" in
            ZT_PORT=*|API_PORT=*|FILE_SERVER_PORT=*|IP_ADDR4=*|IP_ADDR6=*) arguments+=(-e "$env_line") ;;
        esac
    done <<< "$environment"
    probe_settings "$image" "${arguments[@]}" && valid_ports && [[ -n $ipv4 || -n $ipv6 ]]
}

prepare_install() {
    local image=$1 auto answer settings="$ZEROTIER_PATH/.install-settings" temporary
    local -a saved=() arguments=()
    if [[ -f $settings ]]; then
        mapfile -t saved <"$settings" || return 1
        arguments=(-e "ZT_PORT=${saved[0]:-}" -e "API_PORT=${saved[1]:-}" -e "FILE_SERVER_PORT=${saved[2]:-}"
            -e "IP_ADDR4=${saved[3]:-}" -e "IP_ADDR6=${saved[4]:-}")
    fi
    probe_settings "$image" "${arguments[@]}" || return 1
    if valid_ports && [[ -n $ipv4 || -n $ipv6 ]]; then return 0; fi
    if [[ -z $ZT_PORT ]]; then ZT_PORT=$(prompt_port "ZeroTier 端口（例如 9994）：") || return 1; fi
    if [[ -z $API_PORT ]]; then API_PORT=$(prompt_port "管理端口（例如 3443）：") || return 1; fi
    if [[ -z $FILE_PORT ]]; then FILE_PORT=$(prompt_port "下载端口（例如 3000）：") || return 1; fi
    valid_ports || { echo "三个端口必须有效且各不相同。" >&2; return 1; }
    if [[ -z $ipv4 && -z $ipv6 ]]; then
        read -r -p "自动获取公网 IP？(y/n) " auto || return 1
        if [[ $auto == [Yy] ]]; then
            ipv4=$(curl -fsS --max-time 8 https://ipv4.icanhazip.com/) || ipv4=
            ipv6=$(curl -fsS --max-time 8 https://ipv6.icanhazip.com/) || ipv6=
            read -r -p "使用 IPv4 [$ipv4] 和 IPv6 [$ipv6]？(y/n) " answer || return 1
        fi
        if [[ ${answer:-} != [Yy] ]]; then
            read -r -p "公网 IPv4（可留空）：" ipv4 || return 1
            read -r -p "公网 IPv6（可留空）：" ipv6 || return 1
        fi
    fi
    docker run --rm --network none --entrypoint node "$image" /app/settings.js validate \
        "$ZT_PORT" "$API_PORT" "$FILE_PORT" "$ipv4" "$ipv6" || return 1
    # Preserve the very first choices even if Docker cannot create the container.
    # Legacy partial installations belong to the initializer; leave those files intact.
    local existing=
    if [[ -d $ZEROTIER_PATH ]]; then
        existing=$(ls -A -- "$ZEROTIER_PATH") || return 1
    fi
    if [[ -z $existing ]]; then
        mkdir -p -- "$ZEROTIER_PATH" || return 1
        temporary=$(mktemp "$ZEROTIER_PATH/.settings.XXXXXXXX") || return 1
        printf '%s\n' "$ZT_PORT" "$API_PORT" "$FILE_PORT" "$ipv4" "$ipv6" >"$temporary" &&
            mv -f -- "$temporary" "$settings" || return 1
    fi
    return 0
}

resolve_image() {
    local reference=$1 refresh=${2:-cached} id label
    if [[ $reference != sha256:* ]] &&
        { [[ $refresh == refresh ]] || ! docker image inspect "$reference" >/dev/null 2>&1; }; then
        docker pull "$reference" >&2 || return 1
    fi
    id=$(docker image inspect --format '{{.Id}}' "$reference") || return 1
    label=$(docker image inspect --format '{{index .Config.Labels "org.zerotier-planet.retry-safe"}}' "$id") || return 1
    if [[ $label != 1 && $reference == xubiaolin/zerotier-planet:latest && -z ${IMAGE_EXPLICIT:-} ]]; then
        echo "默认镜像尚未包含安全重试支持，正在从当前项目构建新版……" >&2
        # .dockerignore excludes deployment data from the build context.
        id=$(docker build -q "$SCRIPT_DIR") || return 1
        id=$(docker image inspect --format '{{.Id}}' "$id") || return 1
    elif [[ $label != 1 ]]; then
        echo "指定的镜像未包含安全重试支持，请使用当前源码构建的镜像。" >&2
        return 1
    fi
    printf '%s\n' "$id"
}

run_container() {
    local image=$1
    local -a labels=()
    if [[ -n ${UPGRADE_TOKEN:-} ]]; then
        labels+=(--label "org.zerotier-planet.upgrade=$UPGRADE_TOKEN")
    fi
    docker run -d --name "$CONTAINER_NAME" "${labels[@]}" \
        -p "$ZT_PORT:$ZT_PORT" -p "$ZT_PORT:$ZT_PORT/udp" \
        -p "$API_PORT:$API_PORT" -p "$FILE_PORT:$FILE_PORT" \
        -e "IP_ADDR4=$ipv4" -e "IP_ADDR6=$ipv6" -e "ZT_PORT=$ZT_PORT" \
        -e "API_PORT=$API_PORT" -e "FILE_SERVER_PORT=$FILE_PORT" \
        -v "$DIST_PATH:/app/dist" -v "$ZTNCUI_PATH:/app/ztncui" \
        -v "$ZEROTIER_PATH/one:/var/lib/zerotier-one" -v "$CONFIG_PATH:/app/config" \
        --restart unless-stopped "$image"
}

wait_ready() {
    local name=$1 state health diagnostic deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        state=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name") || return 1
        read -r state health <<< "$state"
        case "$state/$health" in
            running/healthy) return 0 ;;
            running/unhealthy|exited/*|dead/*) break ;;
            running/)
                # Images built before HEALTHCHECK expose the same three services.
                if docker exec "$name" sh -ec '
                    cd /app/config
                    test -s /app/dist/planet
                    curl -fsS -m 2 -H "X-ZT1-Auth: $(cat /var/lib/zerotier-one/authtoken.secret)" \
                        "http://127.0.0.1:$(cat zerotier-one.port)/status" >/dev/null
                    curl -fsS -m 2 "http://127.0.0.1:$(cat ztncui.port)/" >/dev/null
                    curl -fsS -m 2 -G --data-urlencode "key=$(cat file_server.key)" \
                        "http://127.0.0.1:$(cat file_server.port)/planet" >/dev/null
                ' >/dev/null 2>&1; then return 0; fi
                ;;
        esac
        if [[ $state == restarting ]]; then
            diagnostic=$(docker logs --tail 30 "$name" 2>&1 | sed -n '/^初始化停止。/p' | tail -1)
            if [[ -n $diagnostic ]]; then break; fi
        fi
        sleep 2
    done
    diagnostic=$(docker logs --tail 30 "$name" 2>&1 | sed -n '/^初始化停止。/p' | tail -1)
    if [[ -n $diagnostic ]]; then echo "$diagnostic" >&2; fi
    echo "容器 $name 未能通过就绪检查。" >&2
    return 1
}

install() {
    local image running retry_safe
    if container_exists "$CONTAINER_NAME"; then
        verify_mounts "$CONTAINER_NAME" || return 1
        running=$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME") || return 1
        retry_safe=$(docker inspect --format '{{index .Config.Labels "org.zerotier-planet.retry-safe"}}' "$CONTAINER_NAME") || return 1
        if [[ $retry_safe != 1 ]]; then
            if [[ $running == true ]] && wait_ready "$CONTAINER_NAME"; then
                info
                return
            fi
            echo "将用可安全重试的镜像和原数据恢复旧版实例。"
            upgrade repair && info
            return
        fi
        if [[ $running != true ]]; then docker start "$CONTAINER_NAME" || return 1; fi
    else
        image=$(resolve_image "$DOCKER_IMAGE") && prepare_install "$image" && run_container "$image" || return 1
    fi
    wait_ready "$CONTAINER_NAME" && info
}

info() {
    local host key moon file
    verify_mounts "$CONTAINER_NAME" && load_config || { echo "无法读取当前部署配置。" >&2; return 1; }
    host=${ipv4:-[$ipv6]}
    echo "管理界面：http://$host:$API_PORT"
    echo "初始管理员：admin；初次安装的默认密码为 password，请在登录后修改。"
    echo "客户端文件目录：$DIST_PATH"
    # Existing installations may use a custom key with characters reserved in URLs.
    key=$(docker exec "$CONTAINER_NAME" node -e '
        const fs = require("fs");
        const key = fs.readFileSync("/app/config/file_server.key", "utf8").replace(/[\r\n]+$/, "");
        if (!key) process.exit(1);
        process.stdout.write(encodeURIComponent(key));
    ') || return 1
    moon=$(docker exec "$CONTAINER_NAME" sh -c 'for file in /app/dist/*.moon; do [ -s "$file" ] && basename "$file"; done') || return 1
    echo "planet 下载：http://$host:$FILE_PORT/planet?key=$key"
    while IFS= read -r file; do
        [[ -z $file ]] || echo "moon 下载：http://$host:$FILE_PORT/$file?key=$key"
    done <<< "$moon"
    echo "使用端口：$ZT_PORT/tcp、$ZT_PORT/udp、$API_PORT/tcp、$FILE_PORT/tcp"
}
