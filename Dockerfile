FROM alpine:3.14 as builder

ENV TZ=Asia/Shanghai

WORKDIR /app
ADD ./entrypoint.sh /app/entrypoint.sh
ADD ./http_server.js /app/http_server.js

# init tool
RUN set -x\
    && apk update\
    && apk add --no-cache git python3 npm make g++ linux-headers curl pkgconfig openssl-dev  jq build-base  gcc \
    && echo "env prepare success!"

# make zerotier-one
RUN set -x\
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y\
    && source "$HOME/.cargo/env"\
    && git clone https://github.com/zerotier/ZeroTierOne.git\
    && cd ZeroTierOne\
    && make ZT_SYMLINK=1 \
    && make\
    && make install\
    && echo "make success!"\
    ; zerotier-one -d  \
    ; sleep 5s && ps -ef |grep zerotier-one |grep -v grep |awk '{print $1}' |xargs kill -9\
    && echo "zerotier-one init success!"


#make ztncui 
RUN set -x \
    && mkdir /app -p \
    &&  cd /app \
    && git clone --progress https://ghproxy.markxu.online/https://github.com/key-networks/ztncui.git\
    && cd /app/ztncui/src \
    && npm config set registry https://registry.npmmirror.com\
    && npm install -g node-gyp\
    && npm install 

FROM alpine:3.14

WORKDIR /app

ENV IP_ADDR4=''
ENV IP_ADDR6=''

ENV ZT_PORT=9994
ENV API_PORT=3443
ENV FILE_SERVER_PORT=3000
ENV GH_MIRROR="https://ghproxy.markxu.online/"

ENV FILE_KEY=''
ENV TZ=Asia/Shanghai

COPY --from=builder /app/ztncui /bak/ztncui
COPY --from=builder /var/lib/zerotier-one /bak/zerotier-one

COPY --from=builder /app/ZeroTierOne/zerotier-one /usr/sbin/zerotier-one
COPY --from=builder /app/entrypoint.sh /app/entrypoint.sh
COPY --from=builder /app/http_server.js /app/http_server.js

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk update \
    && apk add --no-cache npm curl jq\
    && echo "${ZT_PORT}" >/app/zerotier-one.port \
    && echo ${API_PORT}> /app/ztncui.port 


VOLUME [ "/app/dist","/app/ztncui","/var/lib/zerotier-one" ]

CMD ["/bin/sh","/app/entrypoint.sh"]
