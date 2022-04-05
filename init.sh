sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
apk update
apk add git python3 nodejs npm make g++ linux-headers zerotier-one
npm config set registry http://registry.npm.taobao.org && npm install -g node-gyp

echo "下载源码中,源码文件较大，请耐心等待;如果源码下载失败，请重新执行该脚本"
# 下载源码
cd /opt && git clone http://gh-proxy.markxu.vip/https://github.com/key-networks/ztncui.git
cd /opt && git clone http://gh-proxy.markxu.vip/https://github.com/zerotier/ZeroTierOne.git

# 配置ztncui
cd /opt/ztncui/src && npm install argon2 && npm install
cp -pv ./etc/default.passwd ./etc/passwd
echo 'HTTP_PORT=3443' >.env
echo 'NODE_ENV=production' >>.env
echo 'HTTP_ALL_INTERFACES=true' >>.env
