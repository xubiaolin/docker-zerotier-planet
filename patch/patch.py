import os
import json
import re
from socket import getaddrinfo
from re import M


def get_moon():
    with open("/var/lib/zerotier-one/moon.json", "r") as f:
        moon = json.load(f)
        return moon


def get_patch():
    with open("/app/patch/patch.json", "r") as f:
        return json.load(f)

def replace_domain(url):
    domain = re.search(r'\w[\w\.-]+', url).group() 
    ip = getaddrinfo(domain, 80)[0][-1][0]
    return url.replace(domain, ip)

def patch():
    moons = get_moon()
    patches = get_patch()
    text = ''
    for moon, patch in zip(moons["roots"], patches):
        identity = moon["identity"]
        patch["stableEndpoints"] = [replace_domain(url) for url in patch["stableEndpoints"]]
        moon["stableEndpoints"] = patch["stableEndpoints"]

        # 修改world
        text += f"""
        roots.push_back(World::Root());
        roots.back().identity = Identity("{identity}");
        """

        for i in patch["stableEndpoints"]:
            text += f'\n        roots.back().stableEndpoints.push_back(InetAddress("{i}"));'
    # 修改moon  
    with open("/var/lib/zerotier-one/moon.json", "w") as f:
        f.write(json.dumps(moons,sort_keys=True, indent=2))

    print("修改后的moon")
    print(moons)

    # 生成文件
    with open("/app/patch/mkworld.cpp", "r") as cpp:
        world = "".join(cpp.readlines())
        world = world.replace("//__PATCH_REPLACE__", text)

    with open("/app/ZeroTierOne/attic/world/mkworld.cpp", "w") as cpp:
        cpp.write(world)


if __name__ == '__main__':
    patch()
