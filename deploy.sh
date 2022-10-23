#!/bin/bash

function deploy() {
    imageName="zerotier-planet"

    # 处理ip信息
    curr_ip=$(curl -s cip.cc | grep http | awk -F '/' '{print $4}')

    echo "-------------------------------------------"
    echo "支持使用域名或者ip，默认端口为9993，暂不支持修改"
    echo "请输入 ip 或者 域名"
    echo ""
    echo "您当前公网ip为："$curr_ip",使用当前ip请输入:y"
    echo "-------------------------------------------"

    ip=""
    read c

    if [ "$c" = 'y' ]; then
        ip=$curr_ip
    else
        ip=$c
    fi

    echo "----------------------------"
    echo "部署的ip为:$ip, 是否继续? y/n"
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
    docker cp zerotier-planet:/app/bin/planet /opt/planet
    docker run -d --network host --name $imageName --restart unless-stopped -v ./data/zerotier-one:/var/lib/zerotier-one -v ./data/ztncui:/opt/ztncui $imageName
}

function menu() {
    echo
    echo "=============功能菜单============="
    echo "| 1 - 安装"
    #echo "| 2 - 更新"
    #echo "| 3 - 卸载"
    echo "| q - 退出"
    echo "---------------------------------"
    printf "请选择菜单："
    read -n 1 n
    echo
    if [[ "$n" = "1" ]]; then
        echo "安装"
        deploy

    #elif [ "$n" = "2" ]; then
    #    echo $n
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
