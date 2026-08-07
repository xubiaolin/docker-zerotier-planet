#!/bin/sh

set -eu

while :; do
    printf 'READY\n'
    IFS= read -r header || exit 0
    payload_length=$(printf '%s\n' "$header" | sed -n 's/.*len:\([0-9][0-9]*\).*/\1/p')
    [ -n "$payload_length" ] || exit 1
    dd bs=1 count="$payload_length" of=/dev/null 2>/dev/null
    printf 'RESULT 2\nOK'
    kill -TERM 1
done
