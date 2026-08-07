#!/usr/bin/env bats

setup() {
    export TEST_ROOT
    TEST_ROOT=$(mktemp -d)
    export CONFIG_PATH="$TEST_ROOT/config"
    export DIST_PATH="$TEST_ROOT/dist"
    export ZTNCUI_STATE_PATH="$TEST_ROOT/ztncui"
    export ZEROTIER_PATH="$TEST_ROOT/one"
    mkdir -p "$CONFIG_PATH"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

@test "loads explicit values and persists the legacy config layout" {
    export ZT_PORT=19994 API_PORT=13443 FILE_SERVER_PORT=13000
    export IP_ADDR4=203.0.113.10 IP_ADDR6=
    run sh -c '. container/lib/common.sh; . container/lib/config.sh; load_config; persist_config; printf "%s,%s,%s" "$ZT_PORT" "$API_PORT" "$FILE_SERVER_PORT"'
    [ "$status" -eq 0 ]
    [ "$output" = "19994,13443,13000" ]
    [ "$(cat "$CONFIG_PATH/zerotier-one.port")" = 19994 ]
    [ "$(cat "$CONFIG_PATH/ip_addr4")" = 203.0.113.10 ]
}

@test "rejects invalid and duplicate ports" {
    export ZT_PORT=9994 API_PORT=9994 FILE_SERVER_PORT=3000
    export IP_ADDR4=203.0.113.10 IP_ADDR6=
    run sh -c '. container/lib/common.sh; . container/lib/config.sh; load_config'
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be distinct"* ]]
}

@test "requires reconfigure when an identity endpoint changes" {
    printf '9994\n' >"$CONFIG_PATH/zerotier-one.port"
    printf '198.51.100.1\n' >"$CONFIG_PATH/ip_addr4"
    export ZT_PORT=9994 API_PORT=3443 FILE_SERVER_PORT=3000
    export IP_ADDR4=203.0.113.10 IP_ADDR6=
    run sh -c '. container/lib/common.sh; . container/lib/config.sh; load_config'
    [ "$status" -ne 0 ]
    [[ "$output" == *"run deploy.sh reconfigure"* ]]
}

@test "rejects malformed public addresses" {
    export ZT_PORT=9994 API_PORT=3443 FILE_SERVER_PORT=3000
    export IP_ADDR4=not-an-ip IP_ADDR6=
    run sh -c '. container/lib/common.sh; . container/lib/config.sh; load_config'
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid IP_ADDR4"* ]]
}
