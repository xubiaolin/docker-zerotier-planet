FROM alpine:latest

ADD ./init.sh /app/
ADD ./gen_world.sh /app/
ADD ./patch /opt/patch/

VOLUME ["/var/lib/zerotier-one/"]

RUN cd /app && sh init.sh

WORKDIR /app/
CMD /bin/sh -c "zerotier-one -d; cd /opt/ztncui/src;npm start"
