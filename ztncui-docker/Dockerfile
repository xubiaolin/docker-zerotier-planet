FROM keynetworks/ztncui:latest

ADD ./ztncui_0.8.14_amd64.deb /ztncui_0.8.14_amd64.deb

RUN dpkg -i ztncui_0.8.14_amd64.deb

ENTRYPOINT [ "/start_ztncui.sh" ]