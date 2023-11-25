echo "config zerotier"
cd /var/lib/zerotier-one
zerotier-idtool initmoon identity.public >moon.json
if [ -z "$IP_ADDR4" ]; then IP_ADDR4=$(curl -s https://ipv4.icanhazip.com/); fi
if [ -z "$IP_ADDR6" ]; then IP_ADDR6=$(curl -s https://ipv6.icanhazip.com/); fi

echo "IP_ADDR4=$IP_ADDR4"
echo "IP_ADDR6=$IP_ADDR6"

if [ -z "$IP_ADDR4" ]; then stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"; fi
if [ -z "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"; fi
if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"; fi
if [ -z "$IP_ADDR4" ] && [ -z "$IP_ADDR6" ]; then
    echo "IP_ADDR4 and IP_ADDR6 are both empty!"
    exit 1
fi
echo "stableEndpoints=$stableEndpoints"

jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json >temp.json && mv temp.json moon.json

zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d
wget "${GIT_MIRROR}https://github.com/kaaass/ZeroTierOne/releases/download/mkmoonworld-1.0/mkmoonworld-x86_64"
chmod +x mkmoonworld-x86_64

./mkmoonworld-x86_64 moon.json
echo -e "mkmoonworld success!\n"

echo "config ztncui"
cd /app/ztncui/src && echo 'HTTP_PORT=3443' >.env
echo 'NODE_ENV=production' >>.env
echo 'HTTP_ALL_INTERFACES=true' >>.env
echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env && echo "${ZT_PORT}" >/app/zerotier-one.port
cp -v etc/default.passwd etc/passwd

cd /var/lib/zerotier-one && ./zerotier-one -p`cat /app/zerotier-one.port` -d; cd /app/ztncui/src;npm start
