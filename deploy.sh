#!/bin/bash

imageName="zerotier-planet"

function install() {
  read -p "请输入zerotier-planet要使用的端口号,例如9994（数字）: " port

  # 确保端口号是数字
  while ! [[ "$port" =~ ^[0-9]+$ ]]; do
  read -p "端口号必须是数字，请重新输入端口号: " port
  done

  read -p "是否自动获取公网IP地址？（y/n）" use_auto_ip

  if [[ "$use_auto_ip" =~ ^[Yy]$ ]]; then
    ipv4=$(curl -s https://ipv4.icanhazip.com/)
    ipv6=$(curl -s https://ipv6.icanhazip.com/)

    echo "获取到的IPv4地址为: $ipv4"
    echo "获取到的IPv6地址为: $ipv6"

    read -p "是否使用上面获取到的IP地址？（y/n）" use_auto_ip_result

    if [[ "$use_auto_ip_result" =~ ^[Nn]$ ]]; then
      read -p "请输入IPv4地址: " ipv4
      read -p "请输入IPv6地址（可留空）: " ipv6
    fi
  else

    # 要求用户手动输入IP地址
    read -p "请输入IPv4地址: " ipv4
    read -p "请输入IPv6地址（可留空）: " ipv6
  fi

  # 输出使用的端口号和IP地址
  ipv4_entry="${ipv4}/${port}"
  if [[ -n "$ipv6" ]]; then
    ipv6_entry="${ipv6}/${port}"
    endpoints="[\"$ipv4_entry\",\"$ipv6_entry\"]"
  else
    endpoints="[\"$ipv4_entry\"]"
  fi
  echo "{\"stableEndpoints\":$endpoints}" > ./patch/patch.json

  echo "配置内容为:"
  echo "`cat ./patch/patch.json`"

  echo "开始安装..."
  echo "清除原有内容"
  rm -rf /tmp/planet
  docker stop $imageName
  docker rm $imageName
  docker rmi $imageName

  echo "打包镜像"
  echo "使用的端口为：${port}"
  docker build --no-cache --build-arg ZT_PORT=$port --network host -t $imageName .
  if [ $? -ne 0 ]; then
    echo "镜像打包失败，请重试"
    exit 1
  fi

  echo "启动服务"
  for i in $(lsof -i:$port -t); do kill -2 $i; done
  docker run -d -p $port:$port -p $port:$port/udp -p 3443:3443 --name $imageName --restart unless-stopped $imageName
  docker cp zerotier-planet:/app/bin/planet /tmp/planet

  echo "planet文件路径为 /tmp/planet"
  echo "planet server端口为: $port, 请在防火墙放行该端口的tcp和udp协议"
  echo "enjoy~"
}

function upgrade() {
  echo "准备更新zerotier服务"
  docker exec $imageName sh -c "apt update && apt upgrade zerotier-one -y || apk upgrade zerotier-one"
  docker restart $imageName
  echo "done!"
}

# 显示菜单
echo "欢迎使用zerotier-planet脚本，请选择需要执行的操作："
echo "1. 安装"
echo "2. 更新"
echo "3. 复制planet文件到当前目录"
echo "其他任意键退出"

# 读取用户输入
read choice

# 根据用户输入执行相应操作
case "$choice" in
1)
  echo "您选择了安装功能"
  install
  ;;
2)
  echo "您选择了更新功能"
  upgrade
  ;;
3)
  echo "导出planet到当前目录"
  docker cp zerotier-planet:/app/bin/planet .
  ;;
*)
  echo "谢谢使用！"
  exit 0
  ;;
esac
