FROM alpine:3.14 as builder

ENV IP_ADDR4=''
ENV IP_ADDR6=''
ENV ZT_PORT=9994
ENV API_PORT=3443
ENV TZ=Asia/Shanghai
ENV GIT_MIRROR=''

WORKDIR /app
ADD . /app

# init tool
RUN set -x\
    && apk update\
    && apk add --no-cache git python3 npm make g++ linux-headers curl pkgconfig openssl-dev  jq build-base  gcc \
    && echo "env prepare success!"

# make zerotier-one
RUN set -x\
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y\
    && source "$HOME/.cargo/env"\
    && git clone ${GIT_MIRROR}https://github.com/zerotier/ZeroTierOne.git --depth 1\
    && cd ZeroTierOne\
    && make ZT_SYMLINK=1 \
    && make\
    && make install\
    && echo "make success!"\
    ; zerotier-one -d  \
    ; sleep 5s && ps -ef |grep zerotier-one |grep -v grep |awk '{print $1}' |xargs kill -9\
    && echo "zerotier-one init success!"


# make moon
# RUN set -x \
#     && cd /var/lib/zerotier-one \
#     ; zerotier-idtool initmoon identity.public >moon.json \
#     ; if [ -z "$IP_ADDR4" ]; then IP_ADDR4=$(curl -s https://ipv4.icanhazip.com/); fi\
#     ; if [ -z "$IP_ADDR6" ]; then IP_ADDR6=$(curl -s https://ipv6.icanhazip.com/); fi\
#     ; echo "IP_ADDR4=$IP_ADDR4"\
#     ; echo "IP_ADDR6=$IP_ADDR6"\
#     ; if [ -z "$IP_ADDR4" ]; then stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"; fi \
#     ; if [ -z "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"; fi \
#     ; if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"; fi \
#     ; if [ -z "$IP_ADDR4" ] && [ -z "$IP_ADDR6" ]; then echo "IP_ADDR4 and IP_ADDR6 are both empty!"; exit 1; fi\
#     ; echo "stableEndpoints=$stableEndpoints"\
#     ; jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json && mv temp.json moon.json\
#     ; zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d\
#     ; wget "${GIT_MIRROR}https://github.com/kaaass/ZeroTierOne/releases/download/mkmoonworld-1.0/mkmoonworld-x86_64"\
#     && chmod +x mkmoonworld-x86_64\
#     ; ./mkmoonworld-x86_64 moon.json\
#     ; mkdir -p /app/dist/ \
#     ; mv world.bin /app/dist/planet\
#     ; cp *.moon /app/dist/ \
#     ; echo -e "mkmoonworld success!\n"


#make ztncui 
RUN set -x \
    && mkdir /app -p \
    &&  cd /app \
    && git clone --progress https://ghproxy.markxu.online/https://github.com/key-networks/ztncui.git\
    && cd /app/ztncui/src \
    && npm config set registry https://registry.npmmirror.com\
    && npm install -g node-gyp\
    && npm install \
    && echo "HTTP_PORT=${API_PORT}" >.env \
    && echo 'NODE_ENV=production' >>.env \
    && echo 'HTTP_ALL_INTERFACES=true' >>.env \
    && echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env\
    && echo "${ZT_PORT}" >/app/zerotier-one.port \
    && cp -v etc/default.passwd etc/passwd\
    && TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) \
    && echo "ZT_TOKEN=$TOKEN">> .env \
    && echo "make ztncui success!"

FROM alpine:3.14
WORKDIR /app

COPY --from=builder /app/ztncui /app/ztncui
COPY --from=builder /app/entrypoint.sh /app/entrypoint.sh
COPY --from=builder /app/zerotier-one.port /app/zerotier-one.port

COPY --from=builder /app/ZeroTierOne/zerotier-one /usr/sbin/zerotier-one
COPY --from=builder /var/lib/zerotier-one /var/lib/zerotier-one

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk update \
    && apk add --no-cache npm curl

VOLUME [ "/app","/var/lib/zerotier-one" ]

# 设置启动命令
# CMD /bin/sh -c "cd /var/lib/zerotier-one && ./zerotier-one -p`cat /app/zerotier-one.port` -d; cd /app/ztncui/src; npm start"
ENTRYPOINT [ "/app/entrypoint.sh" ]
