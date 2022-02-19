#!/bin/sh
imageName="zerotier-planet"

echo "清除原有内容"
rm -rf /opt/$imageName
docker stop $imageName
docker rm $imageName
docker rmi $imageName

echo "打包镜像"
docker build -t $imageName:latest .

echo "启动服务"
for i in $(lsof -i:9993 -t);do kill -2 $i;done
docker run -d --network host --name $imageName -p 3443:3443 -p 9993:9993 -p 9993:9993/udp -v /opt/$imageName:/var/lib/zerotier-one --restart unless-stopped $imageName:latest
