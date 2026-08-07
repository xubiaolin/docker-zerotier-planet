#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PROJECT_ROOT

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/deploy/common.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/deploy/config.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/deploy/commands.sh"

menu() {
    printf '%s\n' \
        'ZeroTier Planet，请选择操作：' \
        '1. 安装或启动' \
        '2. 查看状态' \
        '3. 更新' \
        '4. 重新配置 Planet' \
        '5. 重置管理密码' \
        '6. 诊断' \
        '7. 卸载（保留数据）' \
        '0. 退出'
    read -r -p '请输入数字：' selection
    case "$selection" in
        1) command_install ;;
        2) command_status ;;
        3) command_upgrade ;;
        4) command_reconfigure ;;
        5) command_reset_password ;;
        6) command_doctor ;;
        7) command_uninstall ;;
        0) return 0 ;;
        *) die '请输入 0-7 之间的数字' ;;
    esac
}

main() {
    command=${1:-menu}
    if [[ $# -gt 0 ]]; then
        shift
    fi
    case "$command" in
        menu) menu ;;
        install | start) command_install "$@" ;;
        status | info) command_status "$@" ;;
        upgrade | update) command_upgrade "$@" ;;
        reconfigure) command_reconfigure "$@" ;;
        reset-password | resetpwd) command_reset_password "$@" ;;
        doctor) command_doctor "$@" ;;
        stop)
            preflight
            ensure_env_file
            compose stop planet
            ;;
        logs)
            preflight
            ensure_env_file
            compose logs --follow planet
            ;;
        uninstall) command_uninstall "$@" ;;
        purge) command_purge "$@" ;;
        help | --help | -h) usage ;;
        *) die "未知命令：$command（运行 ./deploy.sh help 查看帮助）" ;;
    esac
}

main "$@"
