FROM alpine:latest

ENV TZ=Asia/Shanghai

WORKDIR /app
ADD . /app

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk update\
    && mkdir -p /usr/include/nlohmann/ && cd /usr/include/nlohmann/ && wget https://github.com/nlohmann/json/releases/download/v3.10.5/json.hpp \
    && apk add --no-cache git python3 npm make g++ zerotier-one \
    && npm install -g node-gyp\
    && mkdir /app -p &&  cd /app && git clone https://ghproxy.com/https://github.com/key-networks/ztncui.git\
    && cd /app/ztncui/src \
    && npm install \
    && echo 'HTTP_PORT=3443' >.env \
    && echo 'NODE_ENV=production' >>.env \
    && echo 'HTTP_ALL_INTERFACES=true' >>.env \
    && cp -v etc/default.passwd etc/passwd

RUN cd /app && git clone -v https://ghproxy.com/https://github.com/zerotier/ZeroTierOne.git --depth 1\
    && zerotier-one -d && sleep 5s && ps -ef |grep zerotier-one |grep -v grep |awk '{print $1}' |xargs kill -9 \
    && cd /var/lib/zerotier-one && zerotier-idtool initmoon identity.public >moon.json\
    && cd /app/patch && python3 patch.py \
    && cd /var/lib/zerotier-one && zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d \
    && cd /app/ZeroTierOne/attic/world/ && sh build.sh \
    && sleep 5s \
    && cd /app/ZeroTierOne/attic/world/ && ./mkworld \
    && mkdir /app/bin -p && cp world.bin /app/bin/planet \
    && TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) \
    && echo "ZT_TOKEN=$TOKEN">> /app/ztncui/src/.env 


CMD /bin/sh -c "zerotier-one -d; cd /app/ztncui/src;npm start"