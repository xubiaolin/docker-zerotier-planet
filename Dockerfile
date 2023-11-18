# 使用 Alpine Linux 3.17 作为基础镜像
FROM alpine:3.17 as builder

# 定义构建时参数
ARG ZT_PORT

# 设置时区
ENV TZ=Asia/Shanghai

# 设置工作目录
WORKDIR /app

# 复制当前目录下的文件到容器的 /app 目录
ADD . /app

# 安装基础依赖
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk update \
    && apk add --no-cache git python3 npm make g++ linux-headers curl pkgconfig openssl-dev

# 从清华大学镜像源下载并安装 rustup-init
RUN curl -LO https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup/archive/1.26.0/x86_64-unknown-linux-musl/rustup-init \
    && chmod +x rustup-init \
    && ./rustup-init -y --no-modify-path --default-toolchain none \
    && rm rustup-init

# 设置环境变量
ENV PATH="/root/.cargo/bin:${PATH}"

# 设置 Rustup 和 Cargo 的中国大陆镜像源
ENV RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static
ENV RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup
RUN mkdir -p /root/.cargo \
    && echo '[source.crates-io]' > /root/.cargo/config \
    && echo 'replace-with = "ustc"' >> /root/.cargo/config \
    && echo '[source.ustc]' >> /root/.cargo/config \
    && echo 'registry = "https://mirrors.ustc.edu.cn/crates.io-index"' >> /root/.cargo/config

# 安装 Rust 工具链
RUN rustup toolchain install stable

# 克隆和编译 ZeroTier One
RUN git clone --branch main https://ghproxy.markxu.online/https://github.com/zerotier/ZeroTierOne.git /app/ZeroTierOne \
    && cd /app/ZeroTierOne \
    && make ZT_SYMLINK=1 \
    && make install

# 克隆并安装 ztncui
RUN mkdir /app -p && cd /app && git clone --progress https://ghproxy.markxu.online/https://github.com/key-networks/ztncui.git \
    && cd /app/ztncui/src \
    && cp /app/patch/binding.gyp . \
    && echo "开始配置npm环境" \
    && npm install -g --progress --verbose node-gyp --registry=https://registry.npmmirror.com \
    && npm install  --registry=https://registry.npmmirror.com \
    && echo 'HTTP_PORT=3443' >.env \
    && echo 'NODE_ENV=production' >>.env \
    && echo 'HTTP_ALL_INTERFACES=true' >>.env \
    && echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env \
    && echo "${ZT_PORT}" >/app/zerotier-one.port \
    && cp -v etc/default.passwd etc/passwd

# 配置 ZeroTier One
RUN cd /app/ZeroTierOne \
    && ./zerotier-one -d && sleep 5s && ps -ef |grep zerotier-one |grep -v grep |awk '{print $1}' |xargs kill -9 \
    && cd /var/lib/zerotier-one && zerotier-idtool initmoon identity.public >moon.json \
    && cd /app/patch && python3 patch.py \
    && cd /var/lib/zerotier-one && zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d \
    && cd /app/ZeroTierOne/attic/world/ && sh build.sh \
    && sleep 5s \
    && cd /app/ZeroTierOne/attic/world/ && ./mkworld \
    && mkdir /app/bin -p && cp world.bin /app/bin/planet \
    && TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret) \
    && echo "ZT_TOKEN=$TOKEN">> /app/ztncui/src/.env 

# 使用 Alpine Linux 3.17 作为最终镜像
FROM alpine:3.17
WORKDIR /app

# 从构建阶段复制文件
COPY --from=builder /app/ztncui /app/ztncui
COPY --from=builder /app/ZeroTierOne/zerotier-one /usr/sbin/zerotier-one
COPY --from=builder /app/bin /app/bin
COPY --from=builder /app/zerotier-one.port /app/zerotier-one.port
COPY --from=builder /var/lib/zerotier-one /var/lib/zerotier-one

# 安装运行时依赖
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk update \
    && apk add --no-cache npm

# 设置数据卷
VOLUME [ "/app","/var/lib/zerotier-one" ]

# 设置启动命令
CMD /bin/sh -c "cd /var/lib/zerotier-one && ./zerotier-one -p`cat /app/zerotier-one.port` -d; cd /app/ztncui/src; npm start"
