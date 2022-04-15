#!/bin/sh
imageName="zerotier-planet"

# 处理ip信息
curr_ip=$(curl -s cip.cc | grep http | awk -F '/' '{print $4}')

echo "-------------------------------------------"
echo 您当前公网ip为："$curr_ip", 使用当前ip请输入:y
echo "-------------------------------------------"
echo 使用其他ip请输入要使用的ip,例如1.1.1.1
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
" > ./patch/patch.json
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
for i in $(lsof -i:9993 -t);do kill -2 $i;done
docker run -d --network host  --name $imageName -p 3443:3443 -p 9993:9993 -p 9993:9993/udp --restart unless-stopped $imageName
docker cp zerotier-planet:/app/bin/planet /opt/planet
