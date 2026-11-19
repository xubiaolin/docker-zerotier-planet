# Host-side operations shared by installation, recovery and upgrades.

container_exists() {
    docker container inspect "$1" >/dev/null 2>&1
}

verify_mounts() {
    local name=$1 mode=${2:-inspect} dest type writable source expected mounts count=0 running live host
    mounts=$(docker inspect --format '{{range .Mounts}}{{println .Destination .Type .RW .Source}}{{end}}' "$name") || return 1
    while read -r dest type writable source; do
        case "$dest" in
            /app/config) expected=$CONFIG_PATH ;;
            /app/dist) expected=$DIST_PATH ;;
            /app/ztncui) expected=$ZTNCUI_PATH ;;
            /var/lib/zerotier-one) expected=$ZEROTIER_PATH/one ;;
            /app/config/*|/app/dist/*|/app/ztncui/*|/var/lib/zerotier-one/*)
                echo "容器 $name 有额外的数据子挂载 $dest。" >&2
                return 1
                ;;
            *) continue ;;
        esac
        if [[ $type != bind || $writable != true || ! "$source" -ef "$expected" ]]; then
            echo "容器 $name 的 $dest 不属于当前部署，请从原项目目录运行。" >&2
            return 1
        fi
        ((count+=1))
    done <<< "$mounts"
    [[ $count == 4 ]] || { echo "容器的四个数据挂载不完整，请检查原部署。" >&2; return 1; }
    running=$(docker inspect --format '{{.State.Running}}' "$name") || return 1
    if [[ $running == true ]]; then
        live=$(docker exec --user 0 "$name" stat -Lc '%d:%i' \
            /app/config /app/dist /var/lib/zerotier-one /app/ztncui) || return 1
        host=$(stat -Lc '%d:%i' -- "$CONFIG_PATH" "$DIST_PATH" "$ZEROTIER_PATH/one" "$ZTNCUI_PATH") || return 1
        if [[ $live != "$host" ]]; then
            echo "容器 $name 使用的数据挂载与宿主机当前路径不符。" >&2
            return 1
        fi
    elif [[ $mode == data ]]; then
        if ! read_saved_layout "$name"; then
            echo "无法核实停止容器的数据挂载。请核对磁盘并启动原容器后再试。" >&2
            return 1
        fi
    fi
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

normalize_port() {
    [[ $1 =~ ^0*([1-9][0-9]{0,4})$ ]] && (( 10#${BASH_REMATCH[1]} <= 65535 )) || return 1
    printf '%s' "${BASH_REMATCH[1]}"
}

valid_ports() {
    ZT_PORT=$(normalize_port "$ZT_PORT") && API_PORT=$(normalize_port "$API_PORT") &&
        FILE_PORT=$(normalize_port "$FILE_PORT") &&
        [[ $ZT_PORT != "$API_PORT" && $ZT_PORT != "$FILE_PORT" && $API_PORT != "$FILE_PORT" ]]
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
        if normalize_port "$port"; then return 0; fi
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

empty_installation() {
    local image=$1
    [[ ! -d $ZEROTIER_PATH ]] || docker run --rm --network none -v "$ZEROTIER_PATH:/saved:ro" \
        --entrypoint sh "$image" -ec '
            for entry in /saved/.[!.]* /saved/..?* /saved/*; do
                [ -e "$entry" ] || [ -L "$entry" ] || continue
                [ ! -L "$entry" ] || exit 1
                case "${entry##*/}" in
                    .install-settings) test -f "$entry" ;;
                    lost+found) test -d "$entry" ;;
                    config|dist|one|ztncui) test -d "$entry" && test -z "$(ls -A -- "$entry")" ;;
                    *) exit 1 ;;
                esac || exit 1
            done'
}

pending_installation() {
    [[ -f $ZEROTIER_PATH/.install-settings ]] && empty_installation "$1"
}

correct_install_settings() {
    local answer
    read -r -p "是否修改首次安装的端口和地址？(y/n) " answer && [[ $answer == [Yy] ]]
}

prepare_install() {
    local image=$1 mode=${2:-reuse} auto answer settings="$ZEROTIER_PATH/.install-settings" output
    local -a saved=() arguments=()
    probe_settings "$image" || return 1
    if valid_ports && [[ -n $ipv4 || -n $ipv6 ]]; then return 0; fi
    if [[ $mode == reuse && -f $settings ]]; then
        output=$(docker run --rm --network none -v "$ZEROTIER_PATH:/saved:ro" --entrypoint cat \
            "$image" /saved/.install-settings) || return 1
        mapfile -t saved <<< "$output"
        arguments=(-e "ZT_PORT=${saved[0]:-}" -e "API_PORT=${saved[1]:-}" -e "FILE_SERVER_PORT=${saved[2]:-}"
            -e "IP_ADDR4=${saved[3]:-}" -e "IP_ADDR6=${saved[4]:-}")
        probe_settings "$image" "${arguments[@]}" || return 1
        if valid_ports && [[ -n $ipv4 || -n $ipv6 ]]; then return 0; fi
    fi
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
    if empty_installation "$image"; then
        mkdir -p -- "$ZEROTIER_PATH" || return 1
        printf '%s\n' "$ZT_PORT" "$API_PORT" "$FILE_PORT" "$ipv4" "$ipv6" |
            docker run --rm -i --network none -v "$ZEROTIER_PATH:/saved" --entrypoint sh "$image" -ec '
                temporary=$(mktemp /saved/.settings.XXXXXXXX)
                trap '\''rm -f -- "$temporary"'\'' EXIT
                cat > "$temporary"
                mv -f -- "$temporary" /saved/.install-settings' || return 1
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
    label=$(docker image inspect --format '{{index .Config.Labels "org.zerotier-planet.retry-safe"}} {{index .Config.Labels "org.zerotier-planet.secure-admin"}}' "$id") || return 1
    if [[ $label != "1 1" && $reference == xubiaolin/zerotier-planet:latest && -z ${IMAGE_EXPLICIT:-} ]]; then
        echo "默认镜像尚未支持安全重试和新密码流程，正在从当前项目构建新版……" >&2
        # .dockerignore excludes deployment data from the build context.
        id=$(docker build -q "$SCRIPT_DIR") || return 1
        id=$(docker image inspect --format '{{.Id}}' "$id") || return 1
    elif [[ $label != "1 1" ]]; then
        echo "指定的镜像未支持安全重试和新密码流程，请使用当前源码构建的镜像。" >&2
        return 1
    fi
    printf '%s\n' "$id"
}

run_container() {
    local image=$1
    shift
    local -a labels=()
    if [[ -n ${UPGRADE_TOKEN:-} ]]; then
        labels+=(--label "org.zerotier-planet.upgrade=$UPGRADE_TOKEN")
    fi
    if (( ! $# )); then
        set -- -p "$ZT_PORT:$ZT_PORT/tcp" -p "$ZT_PORT:$ZT_PORT/udp" \
            -p "127.0.0.1:$API_PORT:$API_PORT/tcp" -p "$FILE_PORT:$FILE_PORT/tcp" --restart unless-stopped
    fi
    docker run -d --name "$CONTAINER_NAME" "${labels[@]}" "$@" \
        -e "IP_ADDR4=$ipv4" -e "IP_ADDR6=$ipv6" -e "ZT_PORT=$ZT_PORT" \
        -e "API_PORT=$API_PORT" -e "FILE_SERVER_PORT=$FILE_PORT" \
        -v "$DIST_PATH:/app/dist" -v "$ZTNCUI_PATH:/app/ztncui" \
        -v "$ZEROTIER_PATH/one:/var/lib/zerotier-one" -v "$CONFIG_PATH:/app/config" \
        "$image"
}

port_bindings() {
    local name=$1 source=$2 bindings
    bindings=$(docker inspect --format \
        "{{range \$target, \$bindings := .$source}}{{range \$bindings}}{{printf \"%s|%s|%s\\n\" \$target .HostIp .HostPort}}{{end}}{{end}}" \
        "$name") || return 1
    [[ -n $bindings ]] || return 1
    printf '%s\n' "$bindings" | LC_ALL=C sort
}

bindings_include_services() {
    local bindings=$1 port
    for port in "$ZT_PORT/tcp" "$ZT_PORT/udp" "$API_PORT/tcp" "$FILE_PORT/tcp"; do
        if [[ $'\n'$bindings != *$'\n'"$port|"* ]]; then
            echo "缺少容器端口 $port 的宿主机绑定。" >&2
            return 1
        fi
    done
}

verify_published_ports() {
    local name=$1 expected=${2:-} exact=${3:-false} actual target host port found
    local actual_target actual_host actual_port
    actual=$(port_bindings "$name" NetworkSettings.Ports) || { echo "容器没有发布端口。" >&2; return 1; }
    bindings_include_services "$actual" || return 1
    if [[ $exact == true ]]; then
        [[ $actual == "$expected" ]] || { echo "容器发布的端口与升级前不一致。" >&2; return 1; }
        return 0
    fi
    if [[ -z $expected ]]; then
        expected=$(port_bindings "$name" HostConfig.PortBindings) || return 1
    fi
    while IFS='|' read -r target host port; do
        found=false
        while IFS='|' read -r actual_target actual_host actual_port; do
            if [[ $target == "$actual_target" && ( -z $host || $host == "$actual_host" ) &&
                  ( -z $port || $port == "$actual_port" ) ]]; then
                found=true
                break
            fi
        done <<< "$actual"
        if [[ $found == false ]]; then
            echo "容器端口 $target 的宿主机绑定与预期不符。" >&2
            return 1
        fi
    done <<< "$expected"
}

bridge_network() {
    local name=$1 rows network ipam links aliases network_name id alias
    rows=$(docker inspect --format '{{range $network, $endpoint := .NetworkSettings.Networks}}{{printf "%s|%t|%d|%s\n" $network (ne $endpoint.IPAMConfig nil) (len $endpoint.Links) (join $endpoint.Aliases ",")}}{{end}}' "$name") || return 1
    IFS='|' read -r network ipam links aliases <<< "$rows"
    if [[ -z $network || $rows == *$'\n'* || $ipam != false || $links != 0 ]]; then
        echo "需要单个无静态地址或链接的 Docker bridge 网络。" >&2
        return 1
    fi
    network_name=$(docker network inspect --format '{{if eq .Driver "bridge"}}{{.Name}}{{end}}' "$network") || return 1
    [[ $network == "$network_name" ]] || return 1
    if [[ -n $aliases ]]; then
        id=$(docker inspect --format '{{.Id}}' "$name") || return 1
        while IFS= read -r alias; do
            if [[ $alias != "$name" && $alias != "${id:0:12}" && $alias != "${id}" ]]; then
                echo "无法自动保留容器的自定义网络别名 $alias。" >&2
                return 1
            fi
        done <<< "${aliases//,/$'\n'}"
    fi
    printf '%s\n' "$network"
}

prepare_launch_args() {
    local network=$1 policy=$2 bindings=$3 advertised=$4 target host port mapped=
    local -n result=$5
    [[ $network =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ &&
       $policy =~ ^(no|always|unless-stopped|on-failure(:[0-9]+)?)$ ]] || return 1
    bindings_include_services "$bindings" || return 1
    result=(--network "$network" --restart "$policy")
    while IFS='|' read -r target host port; do
        [[ $target =~ ^[0-9]{1,5}/(tcp|udp|sctp)$ && $host =~ ^[0-9a-fA-F.:]*$ ]] || return 1
        if ! port=$(normalize_port "$port"); then
            echo "无法确定 $target 已分配的宿主机端口。请启动原容器后再试。" >&2
            return 1
        fi
        if [[ $target == "$ZT_PORT/udp" && -z $advertised ]]; then
            if [[ -n $mapped && $mapped != "$port" ]]; then
                echo "ZeroTier 的 UDP 绑定需要统一的宿主机端口。" >&2
                return 1
            fi
            mapped=$port
        fi
        if [[ $host == *:* ]]; then host="[$host]"; fi
        result+=(-p "${host:+$host:}$port:$target")
    done <<< "$bindings"
    advertised=$(normalize_port "${advertised:-$mapped}") || return 1
    result+=(-e "ZT_ADVERTISED_PORT=$advertised")
}

advertised_port() {
    local name=$1 saved environment
    if saved=$(read_config zerotier-advertised.port) && [[ -n $saved ]]; then
        normalize_port "$saved"
        return
    fi
    environment=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$name") || return 1
    sed -n 's/^ZT_ADVERTISED_PORT=//p' <<< "$environment"
}

save_launch_settings() {
    local name=$1 network policy retries bindings ids advertised
    network=$(bridge_network "$name") || return 1
    policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}} {{.HostConfig.RestartPolicy.MaximumRetryCount}}' "$name") || return 1
    read -r policy retries <<< "$policy"
    if [[ $policy == on-failure && $retries != 0 ]]; then policy="on-failure:$retries"; fi
    bindings=$(port_bindings "$name" NetworkSettings.Ports) || return 1
    advertised=$(advertised_port "$name") || return 1
    ids=$(stat -Lc '%d:%i' -- "$CONFIG_PATH" "$DIST_PATH" "$ZEROTIER_PATH/one" "$ZTNCUI_PATH") || return 1
    printf '%s\n' "$name" "$network" "$policy" "${ids//$'\n'/ }" "$advertised" "$bindings" |
        docker exec -i --user 0 "$name" sh -ec '
            umask 077
            temporary=$(mktemp /app/config/.launch.XXXXXXXX)
            trap '\''rm -f -- "$temporary"'\'' EXIT
            cat > "$temporary"
            mv -f -- "$temporary" /app/config/.launch-settings
            sync'
}

read_saved_layout() {
    local name=$1 image saved ids
    image=$(docker inspect --format '{{.Image}}' "$name") || return 1
    saved=$(docker run --rm --network none --user 0 -v "$CONFIG_PATH:/saved:ro" --entrypoint cat \
        "$image" /saved/.launch-settings 2>/dev/null) || return 1
    ids=$(stat -Lc '%d:%i' -- "$CONFIG_PATH" "$DIST_PATH" "$ZEROTIER_PATH/one" "$ZTNCUI_PATH") || return 1
    [[ ${saved%%$'\n'*} == "$name" && $(sed -n '4p' <<< "$saved") == "${ids//$'\n'/ }" ]]
}

restore_launch_settings() {
    local image=$1 settings name network policy ids advertised bindings line configured
    local -n launch=$2 exact=$3
    settings=$(docker run --rm --network none --user 0 -v "$CONFIG_PATH:/saved:ro" --entrypoint sh \
        "$image" -ec '
            if test -e /saved/.launch-settings || test -L /saved/.launch-settings; then
                test -f /saved/.launch-settings && test ! -L /saved/.launch-settings
                cat /saved/.launch-settings
            fi') || return 1
    if [[ -z $settings ]]; then
        read -r -p "找不到原容器的端口绑定。是否使用默认绑定重装？(y/n) " line && [[ $line == [Yy] ]]
        return
    fi
    {
        read -r name && read -r network && read -r policy && read -r ids && read -r advertised && bindings=$(cat)
    } <<< "$settings" || return 1
    if [[ $name != "$CONTAINER_NAME" ]]; then echo "保存的容器名为 $name。" >&2; return 1; fi
    configured=$(docker network inspect --format '{{if eq .Driver "bridge"}}{{.Name}}{{end}}' "$network") || return 1
    [[ $configured == "$network" ]] || return 1
    prepare_launch_args "$network" "$policy" "$bindings" "$advertised" launch || return 1
    exact=$bindings
}

initial_password_hint() {
    local name=$1 secure_admin
    secure_admin=$(docker inspect --format '{{index .Config.Labels "org.zerotier-planet.secure-admin"}}' "$name") || return 1
    if [[ $secure_admin == 1 ]] &&
        docker exec "$name" test -s /app/config/.initial-admin-password; then
        printf '领取首次管理员密码：docker exec %q node /app/admin-password.js initial\n' "$name"
    fi
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
    local image state retry_safe mode=reuse expected_bindings= existing_data=false
    local -a launch_args=()
    if container_exists "$CONTAINER_NAME"; then
        verify_mounts "$CONTAINER_NAME" || return 1
        state=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME") || return 1
        retry_safe=$(docker inspect --format '{{index .Config.Labels "org.zerotier-planet.retry-safe"}}' "$CONTAINER_NAME") || return 1
        if [[ $retry_safe != 1 ]]; then
            if [[ $state == running ]] && wait_ready "$CONTAINER_NAME"; then
                info
                return
            fi
            echo "将用可安全重试的镜像和原数据恢复旧版实例。"
            upgrade repair && info
            return
        fi
        if [[ $state == created ]]; then
            image=$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME") || return 1
            if pending_installation "$image"; then
                if correct_install_settings; then mode=reconfigure; fi
                prepare_install "$image" "$mode" || return 1
                docker rm "$CONTAINER_NAME" >/dev/null && run_container "$image" || return 1
            else
                docker start "$CONTAINER_NAME" || return 1
            fi
        elif [[ $state != running ]]; then
            docker start "$CONTAINER_NAME" || return 1
        fi
    else
        image=$(resolve_image "$DOCKER_IMAGE") || return 1
        if empty_installation "$image"; then
            if [[ -f $ZEROTIER_PATH/.install-settings ]] && correct_install_settings; then mode=reconfigure; fi
        else
            existing_data=true
        fi
        prepare_install "$image" "$mode" || return 1
        if [[ $existing_data == true ]]; then
            restore_launch_settings "$image" launch_args expected_bindings || return 1
        fi
        run_container "$image" "${launch_args[@]}" || return 1
    fi
    wait_ready "$CONTAINER_NAME" || return 1
    if [[ -n $expected_bindings ]]; then
        verify_published_ports "$CONTAINER_NAME" "$expected_bindings" true || return 1
    fi
    info || return 1
    if [[ -z $state ]]; then
        save_launch_settings "$CONTAINER_NAME" || return 1
    elif bridge_network "$CONTAINER_NAME" >/dev/null 2>&1; then
        save_launch_settings "$CONTAINER_NAME" || return 1
    fi
    initial_password_hint "$CONTAINER_NAME"
}

info() {
    local host key moon file bindings target address port download_url
    local -a admin_urls=() download_urls=()
    verify_mounts "$CONTAINER_NAME" && load_config || { echo "无法读取当前部署配置。" >&2; return 1; }
    verify_published_ports "$CONTAINER_NAME" || return 1
    bindings=$(port_bindings "$CONTAINER_NAME" NetworkSettings.Ports) || return 1
    while IFS='|' read -r target address port; do
        case "$address" in
            0.0.0.0) host=$ipv4 ;;
            ::) host=${ipv6:+[$ipv6]} ;;
            *:*) host="[$address]" ;;
            *) host=$address ;;
        esac
        [[ -n $host ]] || continue
        if [[ $target == "$API_PORT/tcp" ]]; then admin_urls+=("http://$host:$port"); fi
        if [[ $target == "$FILE_PORT/tcp" ]]; then download_urls+=("http://$host:$port"); fi
    done <<< "$bindings"
    for host in "${admin_urls[@]}"; do echo "管理界面：$host"; done
    if (( ! ${#admin_urls[@]} )); then echo "没有与管理端口绑定同地址族的通告地址。"; fi
    echo "管理员账号：admin"
    echo "客户端文件目录：$DIST_PATH"
    # Existing installations may use a custom key with characters reserved in URLs.
    key=$(docker exec "$CONTAINER_NAME" node -e '
        const fs = require("fs");
        const key = fs.readFileSync("/app/config/file_server.key", "utf8").replace(/[\r\n]+$/, "");
        if (!key) process.exit(1);
        process.stdout.write(encodeURIComponent(key));
    ') || return 1
    moon=$(docker exec "$CONTAINER_NAME" sh -ec '
        for file in /app/dist/*.moon; do
            if [ -s "$file" ]; then basename "$file"; fi
        done') || return 1
    for download_url in "${download_urls[@]}"; do
        echo "planet 下载：$download_url/planet?key=$key"
        while IFS= read -r file; do
            [[ -z $file ]] || echo "moon 下载：$download_url/$file?key=$key"
        done <<< "$moon"
    done
    if (( ! ${#download_urls[@]} )); then echo "没有与下载端口绑定同地址族的通告地址。"; fi
    echo "容器内端口：$ZT_PORT/tcp、$ZT_PORT/udp、$API_PORT/tcp、$FILE_PORT/tcp"
}
