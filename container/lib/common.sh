#!/bin/sh

set -eu

log() {
    level=$1
    shift
    printf '%s component=runtime level=%s message=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*"
}

die() {
    log error "$*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

atomic_write() {
    target=$1
    mode=$2
    temporary="${target}.tmp.$$"
    umask 077
    cat >"$temporary"
    chmod "$mode" "$temporary"
    mv -f "$temporary" "$target"
}

read_first_line() {
    file=$1
    if [ -f "$file" ]; then
        IFS= read -r value <"$file" || true
        printf '%s' "$value"
    fi
}

is_valid_port() {
    case "$1" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}
