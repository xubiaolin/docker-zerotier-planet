#!/bin/sh
imageName="zerotier-planet"


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

sleep 10s 
echo "生成世界"
docker exec -it $imageName sh /app/gen_world.sh
docker cp $imageName:/opt/ZeroTierOne/attic/world/world.bin /opt/planet

echo "------------------"
echo "现在已经配置好了，planet文件在/opt/planet， 客户端连接时需要替换该planet"
