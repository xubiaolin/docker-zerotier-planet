cd /var/lib/zerotier-one && zerotier-idtool initmoon identity.public > moon.json

# 添加补丁
cd /opt/patch && python3 patch.py
cd /var/lib/zerotier-one && zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d

# 生成世界
cd /opt/ZeroTierOne/attic/world/
sh build.sh
./mkworld