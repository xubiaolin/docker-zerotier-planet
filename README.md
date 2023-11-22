TG交流群：https://t.me/+JduuWfhSEPdlNDk1

QQ交流群：

![image](https://user-images.githubusercontent.com/51899048/221509739-7d039726-34a1-4174-b85f-2d0cbf07bd31.png)


- [0: 广告](#0-广告)
- [1：ZeroTier 介绍](#1zerotier-介绍)
- [2：为什么要自建PLANET 服务器](#2为什么要自建planet-服务器)
- [3：开始安装](#3开始安装)
  - [3.1：准备条件](#31准备条件)
    - [3.1.1 安装git](#311-安装git)
    - [3.1.2 安装docker](#312-安装docker)
    - [3.1.3 启动docker](#313-启动docker)
  - [3.2：下载项目源码](#32下载项目源码)
  - [3.3：执行安装脚本](#33执行安装脚本)
  - [3.4 下载 `planet` 文件](#34-下载-planet-文件)
  - [3.5 新建网络](#35-新建网络)
    - [3.5.1 创建网络](#351-创建网络)
- [4.客户端配置](#4客户端配置)
  - [4.1 Windows 配置](#41-windows-配置)
    - [4.2 加入网络](#42-加入网络)
  - [4.2 Linux 客户端](#42-linux-客户端)
  - [4.3 安卓客户端配置](#43-安卓客户端配置)
  - [4.4 MacOS 客户端配置](#44-macos-客户端配置)
- [参考链接](#参考链接)
- [5. 管理面板SSL配置](#5-管理面板ssl配置)
- [6. 卸载](#6-卸载)
- [7: Q\&A：](#7-qa)
  - [1. 为什么我ping不通目标机器？](#1-为什么我ping不通目标机器)
  - [2. IOS客户端怎么用？](#2-ios客户端怎么用)
  - [3. 为什么看不到官方的Planet](#3-为什么看不到官方的planet)
  - [4. 我更换了IP需要怎么处理？](#4-我更换了ip需要怎么处理)
  - [5. PVE lxc 容器没有创建网卡](#5-pve-lxc-容器没有创建网卡)
  - [6. 管理后台忘记密码怎么办：](#6-管理后台忘记密码怎么办)
- [开发计划](#开发计划)
- [风险声明](#风险声明)
- [类似项目](#类似项目)
- [推广](#推广)
- [捐助和支持](#捐助和支持)

# 0: 广告
**不想自己搭建?**

可以加群联系群主按月购买现成服务,或者添加tg: [https://t.me/uxkram](https://t.me/uxkram)

月付低至10￥，年付低至100￥
带宽|流量|费用（每月）|
-|-|-
3Mbit|100G|10￥
10Mbit|100G|18￥
30Mbit|100G|38￥
50Mbit|100G|58￥
100Mbit|100G|98￥
200Mbit|100G|168￥

流量超出后10￥可购买100G

线路为宁波电信

测速图如下：

<img src="./asserts/nb-speed-test.png" width = "800" height = "" alt="图片名称" align=center />

# 1：ZeroTier 介绍

`ZeroTier` 这一类 P2P VPN 是在互联网的基础上将自己的所有设备组成一个私有的网络，可以理解为互联网连接的局域网。最常见的场景就是在公司可以用手机直接访问家里的 NAS，而且是点对点直连，数据传输并不经由第三方服务器中转。

Zerotier 在多设备之间建立了一个 `Peer to Peer VPN（P2PVPN）` 连接，如：在笔记本电脑、台式机、嵌入式设备、云资源和应用。这些设备只需要通过 `ZeroTier One` ( `ZeroTier` 的客户端) 在不同设备之间建立直接连接，即使它们位于 `NAT` 之后。连接到虚拟 LAN 的任何计算机和设备通常通过 `NAT` 或路由器设备与 `Internet` 连接，`ZeroTier One` 使用 `STUN` 和隧道来建立 `NAT` 后设备之间的 VPN 直连。

简单一点说，`Zerotier` 就是通过 `P2P` 等方式实现形如交换机或路由器上 `LAN`   设备的内网互联。

![zerotier](asserts/zerotier-network.png)

**专有名词**

`PLANET` `：行星服务器，Zerotier` 根服务器

`MOON` ：卫星服务器，用户自建的私有根服务器，起到代理加速的作用

`LEAF` ：网络客户端，就是每台连接到网络节点。

我们本次搭建的就是 `PLANET` 行星服务器


# 2：为什么要自建PLANET 服务器
简单来讲就是官方的服务器在海外，我们连接的时候会存在不稳定的情况


# 3：开始安装
##  3.1：准备条件
- 具有公网 `ip` 的服务器（需要开放 3443/tcp 端口，9993/tcp 端口，9993/udp 端口）[这里的9993需要你根据实际情况替换]
- 安装 `docker`、`git`，

### 3.1.1 安装git
```bash
#debian/ubuntu等
apt update && apt install git -y 

#centos等
yum update && yum install git -y 
```

### 3.1.2 安装docker
```bash
curl -fsSL https://get.docker.com |bash 
```

### 3.1.3 启动docker
```bash
service docker start
```
  
## 3.2：下载项目源码
官方地址
```
git clone https://github.com/xubiaolin/docker-zerotier-planet.git
```

加速地址
```
git clone https://ghproxy.markxu.online/https://github.com/xubiaolin/docker-zerotier-planet.git
```

## 3.3：执行安装脚本
进入项目目录
```
cd docker-zerotier-planet
```

运行 `deploy.sh` 脚本
```
./deploy.sh
```

根据提示来选择即可，操作完成后会自动部署
```
欢迎使用zerotier-planet脚本，请选择需要执行的操作：
1. 安装
2. 更新
其他任意键退出

```

整个脚本预计需要 3-10 分钟,具体需要看网络与机型


当您看到类似如下字样时，表示安装成功
```
启动服务                                                                                                                                        
3b59df95edabeabbf19aa6605b28704608710719bdf7c6e7612d75d01ede8f48                                                                                
Preparing to copy...
Copying from container - 512B
Copying from container - 769B
Copying from container - 1.024kB
Copying from container - 1.536kB
Successfully copied 2.048kB to /tmp/planet
planet文件路径为 /tmp/planet
planet server端口为: 9994, 请在防火墙放行该端口的tcp和udp协议
enjoy~
```


## 3.4 下载 `planet` 文件
脚本运行完成后，会在 `/tmp/` 目录下有个 `planet` 文件

下载该文件以备用

## 3.5 新建网络
访问 `http://ip:3443` 进入controller页面

![ui](asserts/ztncui.png)

使用默认账号为:`admin`

默认密码为:`password`

### 3.5.1 创建网络
进入后创建一个网络，可以得到一个网络ID

创建网络，输入名称

![ui](asserts/ztncui_create_net.png)

得到网络 `id`

![ui](asserts/ztncui_net_id.png)


# 4.客户端配置
客户端主要为Windows, Mac, Linux, Android

## 4.1 Windows 配置
首先去zerotier官网下载一个zerotier客户端

将 `planet` 文件覆盖粘贴到`C:\ProgramData\ZeroTier\One`中(这个目录是个隐藏目录，需要运允许查看隐藏目录才行)

Win+S 搜索 `服务`

![ui](asserts/service.png)

找到ZeroTier One，并且重启服务

![ui](asserts/restart_service.png)


### 4.2 加入网络
使用管理员身份打开PowerShell

执行如下命令，看到join ok字样就成功了
```
PS C:\Windows\system32> zerotier-cli.bat join 网络id(就是在网页里面创建的那个网络)
200 join OK
PS C:\Windows\system32>
```

登录管理后台可以看到有个个新的客户端，勾选Authorized就行

![ui](asserts/join_net.png)

执行如下命令：
```
PS C:\Windows\system32> zerotier-cli.bat peers
200 peers
<ztaddr>   <ver>  <role> <lat> <link> <lastTX> <lastRX> <path>
fcbaeb9b6c 1.8.7  PLANET    52 DIRECT 16       8994     1.1.1.1/9993
fe92971aad 1.8.7  LEAF      14 DIRECT -1       4150     2.2.2.2/9993
PS C:\Windows\system32>
```
可以看到有一个 PLANTET 和 LEAF 角色，连接方式均为 DIRECT(直连)

到这里就加入网络成功了

## 4.2 Linux 客户端
步骤如下：

1. 安装linux客户端软件
2. 进入目录 `/var/lib/zerotier-one`
3. 替换目录下的 `planet` 文件
4. 重启 `zerotier-one` 服务(`service zerotier-one restart`)
5. 加入网络 `zerotier-cli join` 网络 `id`
6. 管理后台同意加入请求
7. `zerotier-cli peers` 可以看到` planet` 角色

## 4.3 安卓客户端配置
[Zerotier 非官方安卓客户端发布：支持自建 Moon 节点 - V2EX](https://www.v2ex.com/t/768628)

## 4.4 MacOS 客户端配置
步骤如下：

1. 进入 `/Library/Application\ Support/ZeroTier/One/` 目录，并替换目录下的 `planet` 文件
2. 重启 ZeroTier-One：`cat /Library/Application\ Support/ZeroTier/One/zerotier-one.pid | sudo xargs kill`
3. 加入网络 `zerotier-cli join` 网络 `id`
4. 管理后台同意加入请求
5. `zerotier-cli peers` 可以看到` planet` 角色

# 参考链接
[zerotier-虚拟局域网详解](https://www.glimmer.ltd/2021/3299983056/)

[五分钟自建 ZeroTier 的 Planet/Controller](https://v2ex.com/t/799623)

# 5. 管理面板SSL配置
管理面板的SSL支持需要自行配置，参考Nginx配置如下：
```
upstream zerotier {
  server 127.0.0.1:3443;
}

server {

  listen 443 ssl;

  server_name {CUSTOME_DOMAIN}; #替换自己的域名

  # ssl证书地址
  ssl_certificate    pem和或者crt文件的路径;
  ssl_certificate_key key文件的路径;

  # ssl验证相关配置
  ssl_session_timeout  5m;    #缓存有效期
  ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;    #加密算法
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;    #安全链接可选的加密协议
  ssl_prefer_server_ciphers on;   #使用服务器端的首选算法


  location / {
    proxy_pass http://zerotier;
    proxy_set_header HOST $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

server {
    listen       80;
    server_name  {CUSTOME_DOMAIN}; //替换自己的域名
    return 301 https://$server_name$request_uri;
}
```

# 6. 卸载
```bash
docker rm -f zerotier-planet
```

# 7: Q&A：
## 1. 为什么我ping不通目标机器？
请检查防火墙设置，`Windows` 系统需要允许 `ICMP` 入站，`Linux` 同理

## 2. IOS客户端怎么用？
iOS 客户端插件在这里，设备需要越狱： https://github.com/lemon4ex/ZeroTieriOSFix

## 3. 为什么看不到官方的Planet
该项目剔除了官方服务器，只保留了自定义的Planet节点

## 4. 我更换了IP需要怎么处理？
如果IP更换了，则需要重新部署，相当于全新部署

## 5. PVE lxc 容器没有创建网卡
需要修改lxc容器的配置，同时lxc容器需要取消勾选`无特权`


配置文件位置在`/etc/pve/lxc/{ID}.conf`

在Proxmox7.0之前的版本添加以下内容：
```
lxc.cgroup.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```
在Proxmox7.0之后的版本添加以下内容：
```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

## 6. 管理后台忘记密码怎么办：
建议重装

# 开发计划
🥰您的捐助可以让开发计划的速度更快🥰
- [ ] 多planet支持
- [ ] 3443端口自定义支持
- [ ] planet和controller分离部署


# 风险声明

本项目仅供学习和研究使用，不鼓励用于商业用途。我们不对任何因使用本项目而导致的任何损失负责。


# 类似项目
- [wireguard一键脚本](https://github.com/xubiaolin/wireguard-onekey)

# 推广
京东云主机，安全稳定，性能强劲，新客下单专享特惠

【金秋大促】爆款云主机2核2G3M低至66元首年，优惠直达链接:
https://daili.jd.com/s?linkNo=XF2RVUILETHMCX7BGKAFQHBG2JUUE7S76XQIWTR74W3LQQS6OLTQM5XEITBWPC4WZA6UGATAQLY674QVVELZCIABN4

# 捐助和支持

如果觉得本项目对您有帮助，欢迎通过扫描下方赞赏码捐助项目 :)

<img src="asserts/donate.jpg" alt="donate" width="400" height="400" />
