FROM keynetworks/ztncui:latest

ADD ./ztncui_0.8.14_amd64.deb /ztncui_0.8.14_amd64.deb
ADD ./start_zt1.sh /start_zt1.sh
ADD ./start_ztncui.sh /start_ztncui.sh

RUN dpkg -i ztncui_0.8.14_amd64.deb

ENTRYPOINT [ "/start_ztncui.sh" ]