# make moon
set -x

cd /var/lib/zerotier-one
echo "start mkmoonworld"

zerotier-idtool initmoon identity.public >moon.json

if [ -z "$IP_ADDR4" ]; then IP_ADDR4=$(curl -s https://ipv4.icanhazip.com/); fi
if [ -z "$IP_ADDR6" ]; then IP_ADDR6=$(curl -s https://ipv6.icanhazip.com/); fi

echo "IP_ADDR4=$IP_ADDR4"
echo "IP_ADDR6=$IP_ADDR6"
echo "ZT_PORT=$ZT_PORT"

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
mkdir -p /app/dist/

mv world.bin /app/dist/planet
cp *.moon /app/dist/

echo -e "mkmoonworld success!\n"

echo "start ztncui and zerotier"
sh -c "cd /var/lib/zerotier-one && ./zerotier-one -p$(cat /app/zerotier-one.port) -d; cd /app/ztncui/src; npm start"
