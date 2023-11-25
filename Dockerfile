# FROM alpine:3.17 as builder

# ARG ZT_PORT

# ENV TZ=Asia/Shanghai

# WORKDIR /app
# ADD . /app

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
#     && apk update\
#     && mkdir -p /usr/include/nlohmann/ && cd /usr/include/nlohmann/ && wget https://ghproxy.markxu.online/https://github.com/nlohmann/json/releases/download/v3.10.5/json.hpp \
#     && apk add --no-cache git python3 npm make g++ zerotier-one linux-headers\
#     && mkdir /app -p &&  cd /app && git clone --progress https://ghproxy.markxu.online/https://github.com/key-networks/ztncui.git\
#     && cd /app/ztncui/src \
#     && cp /app/patch/binding.gyp .\
#     && echo "开始配置npm环境"\
#     && npm install -g --progress --verbose node-gyp --registry=https://registry.npmmirror.com\
#     && npm install  --registry=https://registry.npmmirror.com\
#     && echo 'HTTP_PORT=3443' >.env \
#     && echo 'NODE_ENV=production' >>.env \
#     && echo 'HTTP_ALL_INTERFACES=true' >>.env \
#     && echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env\
#     && echo "${ZT_PORT}" >/app/zerotier-one.port \
#     && cp -v etc/default.passwd etc/passwd

# RUN cd /app && git clone --progress https://ghproxy.markxu.online/https://github.com/zerotier/ZeroTierOne.git --depth 1\
#     && zerotier-one -d && sleep 5s && ps -ef |grep zerotier-one |grep -v grep |awk '{print $1}' |xargs kill -9 \
#     && cd /var/lib/zerotier-one && zerotier-idtool initmoon identity.public >moon.json\
#     && cd /app/patch && python3 patch.py \
#     && cd /var/lib/zerotier-one && zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d \
#     && cd /app/ZeroTierOne/attic/world/ && sh build.sh \
#     && sleep 5s \
#     && cd /app/ZeroTierOne/attic/world/ && ./mkworld \
#     && mkdir /app/bin -p && cp world.bin /app/bin/planet \
#     && TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) \
#     && echo "ZT_TOKEN=$TOKEN">> /app/ztncui/src/.env 

# FROM alpine:3.17
# WORKDIR /app

# COPY --from=builder /app/ztncui /app/ztncui
# COPY --from=builder /app/bin /app/bin
# COPY --from=builder /app/zerotier-one.port /app/zerotier-one.port
# COPY --from=builder /var/lib/zerotier-one /var/lib/zerotier-one

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
#     && apk update\
#     && apk add --no-cache npm zerotier-one

# VOLUME [ "/app","/var/lib/zerotier-one" ]

# CMD /bin/sh -c "cd /var/lib/zerotier-one && ./zerotier-one -p`cat /app/zerotier-one.port` -d; cd /app/ztncui/src;npm start"
# #centos等
#--------------------------------------------------------------------------
FROM alpine:3.18  as builder-zt
ARG GIT_MIRROR='https://ghproxy.markxu.online/'

ENV IP_ADDR4=''
ENV IP_ADDR6=''
ENV ZT_PORT=9994
ENV TZ=Asia/Shanghai

WORKDIR /app
ADD . /app

# make zerotier-one
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories\
    && apk update\
    && apk add --no-cache build-base git linux-headers rust cargo pkgconfig openssl-dev curl jq\
    && mkdir -p $HOME/.cargo \
    && echo '[source.crates-io]' > $HOME/.cargo/config.toml \
    && echo 'replace-with = "ustc"' >> $HOME/.cargo/config.toml \
    && echo '[source.ustc]' >> $HOME/.cargo/config.toml \
    && echo 'registry = "https://mirrors.ustc.edu.cn/crates.io-index"' >> $HOME/.cargo/config.toml\
    && git clone ${GIT_MIRROR}https://github.com/zerotier/ZeroTierOne.git --depth 1\
    && cd ZeroTierOne\
    && make && make install\
    && echo "make success!"\
    ; zerotier-one -d  \
    ; sleep 5s && ps -ef |grep zerotier-one |grep -v grep |awk '{print $1}' |xargs kill -9\
    && echo "zerotier-one init success!"


# make moon
RUN cd /var/lib/zerotier-one \
    ; zerotier-idtool initmoon identity.public >moon.json \
    ; if [ -z "$IP_ADDR4" ]; then IP_ADDR4=$(curl -s https://ipv4.icanhazip.com/); fi\
    ; if [ -z "$IP_ADDR6" ]; then IP_ADDR6=$(curl -s https://ipv6.icanhazip.com/); fi\
    ; echo "IP_ADDR4=$IP_ADDR4"\
    ; echo "IP_ADDR6=$IP_ADDR6"\
    ; if [ -z "$IP_ADDR4" ]; then stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"; fi \
    ; if [ -z "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"; fi \
    ; if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"; fi \
    ; if [ -z "$IP_ADDR4" ] && [ -z "$IP_ADDR6" ]; then echo "IP_ADDR4 and IP_ADDR6 are both empty!"; exit 1; fi\
    ; echo "stableEndpoints=$stableEndpoints"\
    ; jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json && mv temp.json moon.json\
    ; zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d\
    ; wget "${GIT_MIRROR}https://github.com/kaaass/ZeroTierOne/releases/download/mkmoonworld-1.0/mkmoonworld-x86_64"\
    && chmod +x mkmoonworld-x86_64\
    ; ./mkmoonworld-x86_64 moon.json\
    ; mkdir -p /app/dist/ \
    ; mv world.bin /app/dist/planet\
    ; cp *.moon /app/dist/ \
    ; echo -e "mkmoonworld success!\n"


# make ztncui
RUN apk add --no-cache nodejs npm python3\
    && npm config set registry https://registry.npm.taobao.org\
    && npm config get registry\
    && git clone ${GIT_MIRROR}https://github.com/key-networks/ztncui.git --depth 1\
    && cd ztncui/src\
    && npm install --python=/usr/bin/python3\
    && echo "make ztncui success!"


# config ztncui
RUN cd /app/ztncui/src\
    &&echo 'HTTP_PORT=3443' >.env \
    && echo 'NODE_ENV=production' >>.env \
    && echo 'HTTP_ALL_INTERFACES=true' >>.env \
    && echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env\
    && echo "${ZT_PORT}" >/app/zerotier-one.port \
    && cp -v etc/default.passwd etc/passwd\
    && TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) \
    && echo "ZT_TOKEN=$TOKEN">> .env 

VOLUME [ "/app/ztncui/etc" ,"/var/lib/zerotier-one"]

# ENTRYPOINT [ "/app/entrypoint.sh" ]
CMD /bin/sh -c "cd /var/lib/zerotier-one && ./zerotier-one -p`cat /app/zerotier-one.port` -d; cd /app/ztncui/src;npm start"