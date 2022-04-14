FROM ubuntu:latest
ENV TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive

Add . /app

RUN cd /app && sh init.sh

WORKDIR /app/
CMD /bin/sh -c "zerotier-one -d; cd /opt/ztncui/src;npm start"
