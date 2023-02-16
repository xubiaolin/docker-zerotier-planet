#!/bin/bash

imageName="zerotier-planet"

function deploy() {

    # 处理ip信息
    curr_ip=$(curl -s cip.cc | grep http | awk -F '/' '{print $4}')

    echo "-------------------------------------------"
    echo 您当前公网ip为："$curr_ip"
    echo
    echo 使用其他ip请输入要使用的ip,例如1.1.1.1,支持使用域名
    echo 使用当前ip请输入:y
    echo "-------------------------------------------"

    ip=""
    read c

    if [ "$c" = 'y' ]; then
        ip=$curr_ip
    else
        ip=$c
    fi

    echo "----------------------------"
    echo "当前的ip为:$ip, 是否继续? y/n"
    read or
    if [ "$or" = "y" ]; then
        echo "{
  \"stableEndpoints\": [
    \"$ip/9993\"
  ]
}
" >./patch/patch.json
    else
        exit -1
    fi

    # 开始安装程序
    echo "清除原有内容"
    rm /opt/planet
    docker stop $imageName
    docker rm $imageName
    docker rmi $imageName

    echo "打包镜像"
    docker build --network host -t $imageName .

    echo "启动服务"
    for i in $(lsof -i:9993 -t); do kill -2 $i; done
    docker run -d -p 9993:9993 -p 9993:9993/udp -p 3443:3443 --name $imageName --restart unless-stopped $imageName
    docker cp zerotier-planet:/app/bin/planet /tmp/planet
}

function upgrade(){
    echo "准备更新zerotier服务"
    docker exec $imageName bash -c "apt update && apt upgrade zerotier-one" -y
    docker restart $imageName
    echo "done!"
}

function menu() {
    echo
    echo "=============功能菜单============="
    echo "| 1 - 安装"
    echo "| 2 - 更新"
    #echo "| 3 - 卸载"
    echo "| q - 退出"
    echo "---------------------------------"
    printf "请选择菜单："
    read -n 1 n
    echo
    if [[ "$n" = "1" ]]; then
        echo "安装"
        deploy

    elif [ "$n" = "2" ]; then
        upgrade
    #elif [ "$n" = "3" ]; then
    #    echo $n
    elif [ "$n" = "q" ]; then
        echo 退出
        return
    else
        echo "错误选项"
    fi
}
menu
