FROM centos:7

WORKDIR /var/lib/zerotier-one/
COPY . /var/lib/zerotier-one/
VOLUME ["/opt","/var/lib/zerotier-one"]
EXPOSE 9993

RUN curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo && \
    yum update -y && \
    yum install git make gcc gcc-c++  python3 wget -y && \
    yum install centos-release-scl -y &&\
    yum install devtoolset-8 -y &&\

    # 编译服务
    cd /opt && \
    git clone https://github.com.cnpmjs.org/zerotier/ZeroTierOne.git && \
    cd ZeroTierOne && \
    make && \
    make install && \

    # 配置moon
    cd /var/lib/zerotier-one && \
    zerotier-idtool generate identity.public identity.secret &&\
    zerotier-idtool initmoon identity.public >> moon.json &&\

    # 配置补丁
    cd /var/lib/zerotier-one && \
    python3 patch.py && \
    zerotier-idtool genmoon moon.json && \
    mkdir moons.d && cp ./*.moon ./moons.d &&\
    rm -rf planet &&\

    # 编译新的plane
    cd /opt/ZeroTierOne/attic/world/ && \
    sh build.sh &&\
    mv world.bin /var/lib/zerotier-one/planet

CMD [ "bash","run.sh" ]




