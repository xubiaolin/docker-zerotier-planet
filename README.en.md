<a href="https://edgeone.ai/?from=github">
  <img src="https://edgeone.ai/media/34fe3a45-492d-4ea4-ae5d-ea1087ca7b4b.png" alt="Logo" /> CDN acceleration and security for this project are sponsored by Tencent EdgeOne
</a>

# Docker ZeroTier Planet

> One‑click deployment of a ZeroTier **Planet** server, with Docker‑based containerized installation.

## 📢 Community

### Telegram
- **Telegram Group**: https://t.me/+JduuWfhSEPdlNDk1

### QQ Groups
- **Group 1**: 692635772
- **Group 2**: 785620313
- **Group 3**: 316239544
- **Group 4**: 1027678459

## 📱 WeChat Official Account
![QR Code](assets/wechat.png)

## ✨ Features

- ✅ Supports **Linux/AMD64** and **Linux/ARM64** architectures
- 🐳 Docker containerized deployment
- 📥 Supports downloading **planet** and **moon** configuration files via URL
- 🌐 Can be deployed as either a **Moon** or **Planet** server
- 🔧 Simple one‑click deployment script
- 📊 Visual, web‑based management UI

## 📋 Table of Contents

- [0. Managed Hosting](#0-managed-hosting)
- [1. What Is ZeroTier?](#1-what-is-zerotier)
- [2. Why Run Your Own PLANET Server?](#2-why-run-your-own-planet-server)
- [3. Getting Started](#3-getting-started)
  - [3.1 Prerequisites](#31-prerequisites)
  - [3.2 Get the Source Code](#32-get-the-source-code)
  - [3.3 Run the Installer](#33-run-the-installer)
  - [3.4 Download the planet File](#34-download-the-planet-file)
  - [3.5 Create a Network](#35-create-a-network)
- [4. Client Configuration](#4-client-configuration)
  - [4.1 Windows](#41-windows)
  - [4.2 Linux](#42-linux)
  - [4.3 Android](#43-android)
  - [4.4 macOS](#44-macos)
  - [4.5 OpenWRT](#45-openwrt)
  - [4.6 iOS](#46-ios)
- [5. SSL for the Management Panel](#5-ssl-for-the-management-panel)
- [6. Uninstall](#6-uninstall)
- [7. FAQ](#7-faq)
- [8. Roadmap](#8-roadmap)
- [9. Risk Statement](#9-risk-statement)
- [10. Related Projects](#10-related-projects)
- [11. Donations & Support](#11-donations--support)
- [12. Acknowledgments](#12-acknowledgments)

---

## 0. Managed Hosting

### 0.1 Managed Container Service

**Looking for a hassle‑free solution?**

We provide professional managed hosting:

| Item | Details |
|------|--------|
| **Trial** | Free 3‑day trial |
| **Annual Fee** | ¥99 per year |
| **Bandwidth** | High‑speed 300 Mbit |
| **Traffic Policy** | 100 GB/month forwarded traffic; once peers connect via P2P, traffic is not counted. Beyond quota: ¥10 per additional 100 GB |
| **Data Center** | Premium route: Ningbo China Telecom |
| **Contact** | Telegram: [https://t.me/uxkram](https://t.me/uxkram), or join a QQ group and contact the admin |

**Speed test:**

<img src="./assets/nb-speed-test.png" width="800" alt="Ningbo DC Speed Test" align="center" />

### 0.2 Rainyun Container Service

[![Deploy on Rainyun](https://rainyun-apps.cn-nb1.rains3.com/materials/deploy-on-rainyun-cn.svg)](https://app.rainyun.com/apps/rca/store/6215?ref=220429)

### 0.3 WeChat Official Account

Follow for the latest updates and technical posts:

<img src="./assets/wx_qrcode_pub.jpg" width="300" alt="WeChat Official Account QR" align="center" />

---

## 1. What Is ZeroTier?

`ZeroTier` is a powerful P2P VPN that lets you create your own virtual LAN over the public Internet. With it, you can easily access devices at home from anywhere—for example, reach your home NAS directly from the office or on mobile. Most importantly, devices connect **peer‑to‑peer** without going through a relay by default, which improves both performance and security.

### How It Works

The `ZeroTier One` client establishes P2P connections among devices (laptops, phones, servers, etc.), even when they are all behind NAT. Using techniques such as STUN, ZeroTier can traverse most NAT types to enable direct device‑to‑device communication. Only when direct connectivity fails does it fall back to relay.

Put simply, `ZeroTier` acts like a **virtual Ethernet switch** spanning the Internet, so devices distributed around the world can talk to each other as if they were on the same LAN.

![zerotier](assets/zerotier-network.png)

### Key Concepts in a ZeroTier Network

| Concept | Description |
|--------|-------------|
| **PLANET** (root servers) | The core root servers for the ZeroTier network. They handle network discovery and initial connections—the “central hub” of the ecosystem. |
| **MOON** (private roots) | User‑operated private root servers. They act as regional anchors to help nearby nodes connect faster and improve network performance. |
| **LEAF** (endpoints) | All devices that join a ZeroTier network—PCs, phones, servers, etc. These endpoints discover and communicate under the coordination of PLANET and MOON. |

This guide walks you through building your **own** private PLANET server so you have full control over your ZeroTier environment.

---

## 2. Why Run Your Own PLANET Server?

### 🚀 Performance
- **Higher stability:** The official roots are overseas; users in mainland China may see high latency and jitter. A self‑hosted PLANET can significantly improve link quality.
- **Faster setup:** A local PLANET server can help nodes establish P2P connectivity more quickly.

### 🔒 Security
- **Full control:** Maintain complete control over your network configuration and tune it for your needs.
- **Better privacy:** Private deployment means your traffic does not traverse third‑party infrastructure by default.

### 💪 Reliability
- **Reduced dependency:** Avoid outages or fluctuations affecting the public root infrastructure.

---

## 3. Getting Started

### 3.1 Prerequisites

Before you begin, make sure your server meets the following:

#### Server
- ✅ Public IPv4 address
- ✅ Open these ports:
  - `3443/tcp` (management UI, adjust if needed)
  - `9994/tcp` (ZeroTier transport, adjust if needed)
  - `9994/udp` (ZeroTier transport, adjust if needed)

#### Software
- ✅ Docker (container runtime)
- ✅ Git (to fetch the repository)

#### OS
A recent Linux distribution is recommended, such as:
- Debian 12
- Ubuntu 20.04+
- Rocky Linux
- Other similar distributions

#### 3.1.1 Install Git

```bash
# Debian/Ubuntu, etc.
apt update && apt install git -y

# CentOS, etc.
yum update && yum install git -y
```

#### 3.1.2 Install Docker

```bash
curl -fsSL https://get.docker.com | bash
```

> **Note:** If network issues prevent installation, you can use a mainland China mirror. See: [Install Docker](https://help.aliyun.com/zh/ecs/use-cases/install-and-use-docker#33f11a5f1800n).

#### 3.1.3 Start Docker

```bash
service docker start
```

#### 3.1.4 (Optional) Configure Docker Registry Mirrors

```bash
sudo tee /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": [
        "https://docker.mirrors.aster.edu.pl",
        "https://docker.mirrors.imoyuapp.win"
    ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 3.2 Get the Source Code

**Official repository:**
```bash
git clone https://github.com/xubiaolin/docker-zerotier-planet.git
```

**Accelerated mirror:**
```bash
git clone https://github.com/xubiaolin/docker-zerotier-planet.git
```

### 3.3 Run the Installer

1. **Enter the project directory:**
```bash
cd docker-zerotier-planet
```

2. **Run the deployment script:**
```bash
./deploy.sh
```

3. **Choose an action:**
```
Welcome to the zerotier-planet script. Choose an action:
1. Install
2. Uninstall
3. Update
4. Show Info
5. Exit
Enter a number:
```

> **Tip:** The script typically completes in 1–3 minutes, depending on your network and hardware.

4. **Successful installation:**

![install-finish](./assets/install_finish.png)

### 3.4 Download the planet File

After the script completes, the `planet` and `moon` configuration files are generated in `./data/zerotier/dist`.

You can retrieve them in either of two ways:

1. **Download from the URL shown upon completion**, or
2. **Use `scp` or another file transfer tool to fetch them from the server**

> **Important:** Keep these files safe—you will need them when configuring clients.

### 3.5 Create a Network

#### 3.5.1 Access the Controller UI

Open `http://<server-ip>:3443` to access the controller.

![ui](assets/ztncui.png)

**Default credentials:**
- Username: `admin`
- Password: `password`

#### 3.5.2 Create a Network

1. After logging in, click **Networks**
2. Click **Add Network**
3. Enter a readable network name; other settings can remain at defaults
4. Click **Create Network**

![ui](assets/ztncui_create_net.png)

A **Network ID** will be generated—record it; you will need it for client setup.

![ui](assets/ztncui_net_id.png)

#### 3.5.3 Assign Network IPs

1. Select **Easy Setup**  
![assign_id](./assets/easy_setup.png)

2. Generate the IP range  
![ip_addr](./assets/network_addr.png)

---

## 4. Client Configuration

ZeroTier clients are available for:

- Windows
- macOS
- Linux
- Android

### 4.1 Windows

#### Step 1: Download the Client
Download the Windows client from the official ZeroTier website.

#### Step 2: Replace the `planet` File
Copy the `planet` file into `C:\ProgramData\ZeroTier\One` (this is a hidden directory—enable “show hidden items”).

#### Step 3: Restart the Service
1. Press `Win + S` and search for **Services**  
![ui](assets/service.png)

2. Locate **ZeroTier One** and restart it  
![ui](assets/restart_service.png)

#### Step 4: Join the Network
Open PowerShell **as Administrator** and run:

```powershell
PS C:\Windows\system32> zerotier-cli.bat join <NETWORK_ID>
200 join OK
PS C:\Windows\system32>
```

> **Note:** `<NETWORK_ID>` is the ID created in the web UI above.

#### Step 5: Authorize the Device
In the management UI, locate the new client and check **Authorized**.

![ui](assets/join_net.png)

The assigned ZeroTier IP will appear under **IP assignment**.

![ip](./assets/allow_devices.png)

#### Step 6: Verify Connectivity
Run:

```powershell
PS C:\Windows\system32> zerotier-cli.bat peers
200 peers
<ztaddr>   <ver>  <role> <lat> <link> <lastTX> <lastRX> <path>
fcbaeb9b6c 1.8.7  PLANET    52 DIRECT 16       8994     1.1.1.1/9993
fe92971aad 1.8.7  LEAF      14 DIRECT -1       4150     2.2.2.2/9993
PS C:\Windows\system32>
```

You should see both a `PLANET` and a `LEAF` peer with `DIRECT` links.

### 4.2 Linux

**Steps:**

1. Install the Linux ZeroTier client
2. Go to `/var/lib/zerotier-one`
3. Replace the `planet` file in that directory
4. Restart the service: `service zerotier-one restart`
5. Join the network: `zerotier-cli join <NETWORK_ID>`
6. Approve the join request in the management UI
7. Run `zerotier-cli peers` and verify the `PLANET` role appears

### 4.3 Android

We recommend the [Unofficial Android Client](https://github.com/kaaass/ZerotierFix).

### 4.4 macOS

**Steps:**

1. Go to `/Library/Application\ Support/ZeroTier/One/` and replace the `planet` file
2. Restart ZeroTier‑One: `cat /Library/Application\ Support/ZeroTier/One/zerotier-one.pid | sudo xargs kill`
3. Join the network: `zerotier-cli join <NETWORK_ID>`
4. Approve the join request in the management UI
5. Run `zerotier-cli peers` and verify the `PLANET` role appears

### 4.5 OpenWRT

**Steps:**

1. Install the ZeroTier client
2. Go to `/etc/config/zero/planet`
3. Replace the `planet` file
4. In the OpenWRT web UI, **stop** ZeroTier, then **start** it again
5. Join the network from the OpenWRT web UI
6. Approve the join request in the management UI
7. Run `ln -s /etc/config/zero /var/lib/zerotier-one`
8. Run `zerotier-cli peers` and verify the `PLANET` role appears

### 4.6 iOS

**Option 1: Jailbreak**  
Install ZeroTier and replace the `planet` file (requires a jailbroken device).

**Option 2: WireGuard**  
Use WireGuard to access the ZeroTier network indirectly.

---

## 5. SSL for the Management Panel

Set up SSL via a reverse proxy (e.g., Nginx). Example configuration:

```nginx
upstream zerotier {
  server 127.0.0.1:3443;
}

server {
  listen 443 ssl;
  server_name {CUSTOM_DOMAIN}; # Replace with your domain

  # SSL certificate paths
  ssl_certificate     <path to .pem or .crt>;
  ssl_certificate_key <path to .key>;

  # SSL tuning
  ssl_session_timeout  5m;
  ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_prefer_server_ciphers on;

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
    server_name  {CUSTOM_DOMAIN}; # Replace with your domain
    return 301 https://$server_name$request_uri;
}
```

---

## 6. Uninstall

```bash
docker rm -f zerotier-planet
```

---

## 7. FAQ

### Q1: Why can’t I ping the target machine?
**A:** Check firewall rules. On **Windows**, allow inbound **ICMP**. Apply equivalent settings on **Linux**.

### Q2: How can I use ZeroTier on iOS?
**A:** There is a plugin here (requires a jailbroken device): https://github.com/lemon4ex/ZeroTieriOSFix

### Q3: Why don’t I see the official PLANET peers?
**A:** This project removes the official roots and uses only your custom PLANET nodes.

### Q4: What if my server’s IP changes?
**A:** Re‑deploy (treat it as a fresh installation).

### Q5: PVE LXC container has no network interface?
**A:** Modify the LXC configuration and uncheck “unprivileged.” The config file is at `/etc/pve/lxc/{ID}.conf`.

**For Proxmox < 7.0, add:**
```
lxc.cgroup.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

**For Proxmox ≥ 7.0, add:**
```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

### Q6: Forgot the management password?
**A:** Run `./deploy.sh` and select the option to reset the password.

### Q7: Can’t connect to PLANET?
**A:** Check firewalls. If you’re on Alibaba Cloud, Tencent Cloud, etc., open the required ports in the provider console. Also open them on Linux itself (e.g., `ufw`).

### Q8: How do I know if I’m direct or relayed?
**A:** Run `zerotier-cli peers` with admin privileges:

```
<ztaddr>   <ver>  <role> <lat> <link>   <lastTX> <lastRX> <path>
69c0d507d0 -      LEAF      -1 RELAY
93caa675b0 1.12.2 PLANET  -894 DIRECT   4142     4068     110.42.99.46/9994
ab403e2074 1.10.2 LEAF      -1 RELAY
```

If your peer shows `RELAY`, traffic is being relayed.

### Q9: Why is my ZeroTier throughput unstable?
**A:** ZeroTier uses UDP. Some regions may apply QoS to UDP. Consider OpenVPN if necessary.

### Q10: Do you support custom domains?
**A:** Not yet.

### Q11: Can I deploy on ARM servers?
**A:** Yes.

### Q12: Do you support `docker-compose`?
**A:** Yes—sample configuration:

```yaml
version: '3'

services:
  myztplanet:
    image: xubiaolin/zerotier-planet:latest
    container_name: ztplanet
    ports:
      - 9994:9994
      - 9994:9994/udp
      - 3443:3443
      - 3000:3000
    environment:
      - IP_ADDR4=[IPV4IP ADDRESS]
      - IP_ADDR6=
      - ZT_PORT=9994
      - API_PORT=3443
      - FILE_SERVER_PORT=3000
    volumes:
      - ./data/zerotier/dist:/app/dist
      - ./data/zerotier/ztncui:/app/ztncui
      - ./data/zerotier/one:/var/lib/zerotier-one
      - ./data/zerotier/config:/app/config
    restart: unless-stopped
```

---

## 8. Roadmap

🥰 Your support accelerates development 🥰

- [ ] Multi‑PLANET support
- [x] Customizable port 3443
- [ ] Split deployment of PLANET and controller

---

## 9. Risk Statement

This project is for learning and research only. Commercial use is **not** encouraged. We are not liable for any loss incurred from using this project.

---

## 10. Related Projects

- [WireGuard One‑Click Script](https://github.com/xubiaolin/wireguard-onekey)

---

## 11. Donations & Support

If this project helps you, consider supporting development:

<img src="assets/donate.png" alt="Donate" width="400" height="400" />

---

## 12. Acknowledgments

Thanks to the following supporters—your encouragement keeps this project going.

**In chronological order:**
- 随性
- 我
- 你好
- Calvin
- 小猪猪的饲养员
- 情若犹在
- 天天星期天
- 啊乐
- 夏末秋至
- **忠
- 岸芷汀兰
- Kimi Chen
- 匿名
- 阳光报告旷课
- 濂溪先生
- Water
- 匿名
- 匿名
- 陆
- 精钢葫芦娃
- 唯
- 王小新
- 匿名
- Duck不必

---

## 📚 References

- [ZeroTier—Virtual LAN Explained](https://www.glimmer.ltd/2021/3299983056/)
- [Build a ZeroTier Planet/Controller in 5 Minutes](https://v2ex.com/t/799623)
