FROM alpine:latest as builder

ARG ZT_PORT

ENV TZ=Asia/Shanghai

WORKDIR /app
ADD . /app

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk update\
    && mkdir -p /usr/include/nlohmann/ && cd /usr/include/nlohmann/ && wget https://ghproxy.com/https://github.com/nlohmann/json/releases/download/v3.10.5/json.hpp \
    && apk add --no-cache git python3 npm make g++ zerotier-one \
    && npm install -g node-gyp\
    && mkdir /app -p &&  cd /app && git clone https://ghproxy.com/https://github.com/key-networks/ztncui.git\
    && cd /app/ztncui/src \
    && cp /app/patch/binding.gyp .\
    && npm install \
    && echo 'HTTP_PORT=3443' >.env \
    && echo 'NODE_ENV=production' >>.env \
    && echo 'HTTP_ALL_INTERFACES=true' >>.env \
    && echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env\
    && echo "${ZT_PORT}" >/app/zerotier-one.port \
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

FROM alpine:latest
WORKDIR /app

COPY --from=builder /app/ztncui /app/ztncui
COPY --from=builder /app/bin /app/bin
COPY --from=builder /var/lib/zerotier-one /var/lib/zerotier-one

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk update\
    && apk add --no-cache npm 


CMD /bin/sh -c "cd /var/lib/zerotier-one && ./zerotier-one -p`cat /app/zerotier-one.port` -d; cd /app/ztncui/src;npm start"
