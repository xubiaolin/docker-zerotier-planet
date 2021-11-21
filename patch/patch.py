import os
import json


def patch_moon():
    patch_data = dict()
    with open("patch.json", "r") as f:
        patch_data = json.load(f)

    moon = dict()
    with open("moon.json", "r") as f:
        moon = json.load(f)

    endpoint_patch = patch_data.get("stableEndpoints", [])
    if len(endpoint_patch) == 0:
        print("请配置endpoint!")
        exit(1)

    moon["roots"][0]["stableEndpoints"] = endpoint_patch

    with open("moon.json", "w+") as f:
        f.write(json.dumps(moon))


def patch_world():
    moon = dict()

    file_moon = open("moon.json", "r")
    moon = json.load(file_moon)
    file_moon.close()

    middle = '''
    //China
    roots.push_back(World::Root());
    roots.back().identity = Identity("{}");'''.format(moon["roots"][0]["identity"])

    for i in moon["roots"][0]["stableEndpoints"]:
        middle += '\n    roots.back().stableEndpoints.push_back(InetAddress("{}"));'.format(i)

    with open("mkworld.cpp", "r") as cpp:
        code = "".join(cpp.readlines())

    with open("mknewworld.cpp", "w+") as cpp:
        code = code.replace("	//__PATCH_REPLACE__", middle)
        print(code)
        cpp.write(code)


if __name__ == '__main__':
    patch_moon()
    patch_world()
