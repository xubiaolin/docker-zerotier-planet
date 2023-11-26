FROM alpine:3.18  as builder-zt

ENV TZ=Asia/Shanghai
ENV GIT_MIRROR='https://ghproxy.markxu.online/'

# make zerotier-one
RUN set -x ;sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories\
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

FROM alpine:3.18
ENV TZ=Asia/Shanghai

COPY --from=builder-zt /usr/sbin/zerotier-one /usr/sbin/zerotier-one
COPY --from=builder-zt /var/lib/zerotier-one /var/lib/zerotier-one

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories\
    &&apk add --no-cache libstdc++ libgcc

CMD /bin/sh -c "cd /var/lib/zerotier-one && ./zerotier-one"