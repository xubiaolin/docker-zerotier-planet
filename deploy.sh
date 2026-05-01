#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZTPLANET="${SCRIPT_DIR}/scripts/ztplanet.sh"

menu() {
  echo "欢迎使用 zerotier-planet 兼容菜单，请选择需要执行的操作："
  echo "1. 安装 / 启动"
  echo "2. 卸载"
  echo "3. 更新"
  echo "4. 查看信息"
  echo "5. 重置密码"
  echo "6. 环境检查"
  echo "0. 退出"
  read -r -p "请输入数字：" num
  case "$num" in
    1) "$ZTPLANET" install ;;
    2) "$ZTPLANET" uninstall ;;
    3) "$ZTPLANET" upgrade ;;
    4) "$ZTPLANET" info ;;
    5) "$ZTPLANET" reset-password ;;
    6) "$ZTPLANET" doctor ;;
    0) exit 0 ;;
    *) echo "请输入正确数字 [0-6]" >&2; exit 1 ;;
  esac
}

if [[ $# -gt 0 ]]; then
  "$ZTPLANET" "$@"
else
  menu
fi
