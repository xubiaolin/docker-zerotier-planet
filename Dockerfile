FROM alpine:latest

ADD ./run.sh /app/
ADD ./patch /opt/patch/

VOLUME ["/var/lib/zerotier-one/"]



RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories &&\
    apk update &&\
    apk add git python3 nodejs npm make g++  linux-headers zerotier-one &&\
    npm config set registry http://registry.npm.taobao.org  &&\
   
    # 安装ztncui
    cd /opt && git clone https://github.com.cnpmjs.org/key-networks/ztncui.git  &&\
    cd ztncui/src && npm install -g node-gyp && npm install &&\
    cp -pv ./etc/default.passwd ./etc/passwd &&\
    echo 'HTTP_PORT=3443' > .env&&\
    echo 'NODE_ENV=production' >> .env &&\
    echo 'HTTP_ALL_INTERFACES=true' >> .env &&\

    # 添加补丁
    cd /opt && \
    git clone https://github.com.cnpmjs.org/zerotier/ZeroTierOne.git && \

    cd /var/lib/zerotier-one && \
    zerotier-idtool generate identity.public identity.secret &&\
    zerotier-idtool initmoon identity.public >> moon.json &&\

    cp /opt/patch/* . &&\
    python3 patch.py &&\
    zerotier-idtool genmoon moon.json &&\
    mkdir moons.d && cp ./*.moon ./moons.d &&\

    rm /opt/ZeroTierOne/attic/world/mkworld.cpp &&\
    cp mkworld.cpp /opt/ZeroTierOne/attic/world/ &&\
    cd /opt/ZeroTierOne/attic/world/ && \
    sh build.sh &&\
    cp ./world.bin /var/lib/zerotier-one/planet

WORKDIR /app/
CMD ["sh","./run.sh"]
