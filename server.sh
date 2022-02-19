#!/bin/sh
echo "开始执行"
zerotier-one -d 

cd /opt/ztncui/src
npm start
