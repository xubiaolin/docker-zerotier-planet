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
    docker run -d --network host --name $imageName --restart unless-stopped --volume ztncui:/opt/key-networks/ztncui/etc/ --volume zt1:/var/lib/zerotier-one/ $imageName 
    docker cp zerotier-planet:/app/bin/planet /opt/planet
}

function migrate() {

    echo "-------------------------------------------"
    echo PS: 请事先确保对端主机满足以下条件:
    echo a. ssh用户可以免密sudo
    echo b. selinux关闭
    echo c. 对端已经安装了docker/podman-docker
    echo 另外,替换了planet的主机需要自行手动下载新的planet文件进行替换
    echo "-------------------------------------------"
    echo "请输入对端ip："

    read remote_ip

    echo "----------------------------"
    echo "对端ip为:$remote_ip, 请输入对端端口:"

    read remote_port
    
    echo "----------------------------"
    echo "对端ip为:$remote_ip, 对端端口为:$remote_port, 请输入对端用户："

    read remote_user
    
    docker stop $imageName
    docker run --rm --volume ./ztncui:/from alpine ash -c "cd /from ; tar -cf - . " | ssh $remote_user@$remote_ip -p $remote_port 'sudo docker run --rm -i --volume ztncui:/to alpine ash -c "cd /to ; tar -xpvf - " '
    docker run --rm --volume ./zt1:/from alpine ash -c "cd /from ; tar -cf - . " | ssh $remote_user@$remote_ip -p $remote_port  'sudo docker run --rm -i --volume zt1:/to alpine ash -c "cd /to ; tar -xpvf - " '
    
    echo "----------------------------"
    echo 迁移完成，请在对端主机执行部署命令：
    echo "git clone https://github.com/m4d3bug/docker-zerotier-planet && ./docker-zerotier-planet/deploy.sh"
    echo "----------------------------"
}

function menu() {
    echo
    echo "=============功能菜单============="
    echo "| 1 - 安装"
    echo "| 2 - 迁移"
    #echo "| 3 - 更新"
    echo "| q - 退出"
    echo "---------------------------------"
    printf "请选择菜单："
    read -n 1 n
    echo
    if [[ "$n" = "1" ]]; then
        echo "安装"
        deploy

    elif [ "$n" = "2" ]; then
        echo "迁移"
        migrate

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
