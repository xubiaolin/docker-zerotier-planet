# Docker ZeroTier Planet

[简体中文](README.md) · [English](README.en.md)

使用 Docker 在 Linux 服务器上部署自己的 ZeroTier Planet，同时提供网络管理界面和 `planet` / `moon` 文件下载服务。适合希望自行管理 ZeroTier 根节点与网络的用户。

> **先了解：**客户端需要替换 `planet` 文件才能使用自建 Planet；自建根节点不保证设备间一定直连，也不等于所有业务流量都经过或都不经过这台服务器。管理界面默认通过 **HTTP** 访问，部署后请尽快修改默认密码。

<a href="https://edgeone.ai/?from=github">
  <img src="assets/edgeone-logo.png" alt="EdgeOne Logo" /> 本项目的 CDN 加速和安全保护由腾讯 EdgeOne 赞助
</a>

## 广告

- [雨云容器服务一键部署-买服务器上雨云](https://app.rainyun.com/apps/rca/store/6215?ref=220429)
- [MyHeadScale-5台设备永久免费-不限流量](https://hs.bj.markxu.vip/?from=github)
- [Bandwagonhost-CN2 优质线路](https://bandwagonhost.com/aff.php?aff=82099)

## 交流与支持

- [Telegram 交流群](https://t.me/+JduuWfhSEPdlNDk1)
- QQ 群：
  - 692635772
  - 785620313
  - 316239544
  - 1027678459
  - 651935808

如果项目对你有帮助，也可以支持该项目

<img src="assets/donate.png" width="180">

微信公众号：

<img src="assets/wx_qrcode_pub.jpg" width="180" alt="微信公众号二维码" />

## 阅读导航

- [广告](#广告)
- [交流与支持](#交流与支持)
- [快速开始](#快速开始)：准备服务器、部署容器、创建网络
- [客户端接入](#客户端接入)：分平台替换 `planet` 并加入网络
- [运维与安全](#运维与安全)：数据备份、更新、卸载、Compose 与 HTTPS
- [常见问题](#常见问题)：连接、端口、IP 变更等
- [项目与社区](#项目与社区)：开发计划、风险声明、致谢与参考资料

## 快速开始

### 1. 准备服务器

准备一台有**公网 IPv4 地址**的 Linux 服务器，安装 Docker 和 Git。部署脚本面向 Linux；镜像构建脚本面向 `linux/amd64` 和 `linux/arm64`。尚未安装 Docker 时，可参考 [Docker 官方安装文档](https://docs.docker.com/engine/install/)。

在服务器防火墙和云平台安全组中放行实际使用的端口（安装时可按提示修改默认值）：

| 默认端口 | 协议 | 用途 |
| --- | --- | --- |
| `9994` | TCP、UDP | ZeroTier 通信 |
| `3443` | TCP | Web 管理界面，默认是 **HTTP**，不是 HTTPS |
| `3000` | TCP | `planet` / `moon` 文件下载服务；仅在需要远程下载时对外开放 |

> 不建议将管理界面或文件下载入口直接暴露给不受信任的访问者。下载链接中的密钥也应当按凭据保管。

### 2. 运行部署脚本

```bash
git clone https://github.com/xubiaolin/docker-zerotier-planet.git
cd docker-zerotier-planet
./deploy.sh
```

按提示选择 **1. 安装**，依次填写 ZeroTier、管理界面和文件下载端口，并选择自动获取或手动填写服务器公网 IP。

部署脚本使用 `docker run` 创建容器；仓库没有自带的 Compose 配置文件。

**已有部署不要直接选择重新安装：该流程会删除当前项目目录下的 `data/zerotier/`，请先备份，升级请选“更新”。**若镜像拉取失败，先确认 Docker 可以访问镜像仓库，不要直接覆盖服务器现有的 Docker 配置。

请在项目目录运行脚本：数据路径按当前工作目录计算。

部署后可检查容器和日志：

```bash
docker ps --filter name=myztplanet
docker logs myztplanet
```

### 3. 创建网络并下载文件

1. 打开 `http://<服务器公网 IP>:3443`（若修改了管理端口，请使用实际端口）并登录。**默认用户名为 `admin`，默认密码为 `password`；首次登录后立即修改密码。**
2. 在 **Networks** 页面点击 **Add Network**，填写名称并创建网络，记下生成的 **Network ID**。需要自动分配虚拟 IP 时，在网络设置中使用 **Easy Setup** 配置地址段。
3. 从部署完成时脚本给出的下载地址，或从服务器的 `./data/zerotier/dist/` 获取 `planet` 文件，将它分发给需要连接此私有 Planet 的客户端。`moon` 文件同样生成在该目录中，本项目已把节点自身配置为 moon，其他节点按需下载使用。

![管理界面与网络列表](assets/ztncui.png)

> **请备份整个 `data/zerotier/` 目录。**其中不仅有供客户端下载的文件，还包含节点身份、签名密钥、控制器和管理界面数据。不要将该目录或下载密钥提交到公开仓库。

### 这套部署包含什么

| 组件 | 作用 |
| --- | --- |
| Planet | ZeroTier 根节点，帮助客户端发现网络；客户端需使用本项目生成的 `planet` 文件 |
| Moon | 部署时会把本节点同时配置为 moon，并在 `dist` 目录生成 `.moon` 文件，供其他节点按需使用 |
| Controller / Web 管理界面 | 创建网络、授权成员并管理地址分配 |
| 文件下载服务 | 提供生成文件的下载入口；下载密钥需要妥善保存 |

ZeroTier 会尝试让节点直接通信；是否能够直连仍取决于双方网络、NAT 和防火墙环境。自建 Planet 不能替代端到端连通性排查。

## 客户端接入

**通用流程：**在客户端安装 ZeroTier → 备份原有 `planet`（如果存在）→ 放入服务器生成的新文件 → 重启 ZeroTier 服务 → 加入创建的 Network ID → 在管理界面授权设备 → 检查分配地址和连接状态。

下面命令中的 `0123456789abcdef` 仅作为 **Network ID 示例**，执行时请替换为自己创建的 ID。不同发行版或客户端版本的安装路径可能不同，请以实际安装位置为准。

### Windows

1. 安装 [ZeroTier One 客户端](https://www.zerotier.com/download/)，将生成的 `planet` 放到 `C:\ProgramData\ZeroTier\One\planet`（`ProgramData` 默认隐藏）；覆盖前备份原文件。
2. 在 Windows“服务”中重启 **ZeroTier One**，再在可调用 `zerotier-cli.bat` 的管理员终端加入网络：

   ```powershell
   zerotier-cli.bat join 0123456789abcdef
   zerotier-cli.bat peers
   ```

3. 在管理界面的成员列表中勾选该设备的 **Authorized**，确认它获得虚拟 IP。`peers` 输出中可查看 Planet 和其他节点的连接状态；**Planet 为 DIRECT 不代表所有设备之间也都直连**。

![Windows 服务管理](assets/restart_service.png)

### Linux

将 `planet` 备份并复制到 ZeroTier 数据目录（通常是 `/var/lib/zerotier-one/planet`），重启服务，然后加入网络：

```bash
sudo cp planet /var/lib/zerotier-one/planet
sudo systemctl restart zerotier-one
sudo zerotier-cli join 0123456789abcdef
sudo zerotier-cli peers
```

覆盖前请先备份目标路径已有的文件；如果系统没有使用 systemd，请使用该系统对应的服务管理命令。最后回到管理界面授权该设备。

### macOS

将 `planet` 备份并放入 `/Library/Application Support/ZeroTier/One/`，重启 ZeroTier One 后加入网络，并在管理界面授权。路径中包含空格；使用终端操作时需要正确引用路径。服务重启方式以当前安装版本为准。

### OpenWrt

先确认所安装的 ZeroTier 插件是否支持自定义 `planet`，以及它实际使用的数据目录。部分插件使用 `/etc/config/zero/planet`；放入文件后在 OpenWrt 管理界面重启 ZeroTier，再加入网络并授权设备。**不要在未核实目录的情况下直接创建或覆盖系统软链接。**

### Android 与 iOS

- **Android：**可参考支持自定义 Planet 的第三方客户端 [ZerotierFix](https://github.com/kaaass/ZerotierFix)，使用前请自行检查其版本兼容性及维护状态。
- **iOS：**替换 `planet` 需要客户端或系统提供相应能力；可了解 [ZeroTieriOSFix](https://github.com/lemon4ex/ZeroTieriOSFix) 等非官方方案，其适用条件和风险由使用者自行评估。**WireGuard 是另一种协议，不能直接作为 ZeroTier 客户端加入本项目创建的网络。**

## 运维与安全

### 数据目录与备份

部署脚本将以下宿主机目录挂载进容器；备份时应保留整个 `data/zerotier/`，而不只是 `planet` 文件：

| 宿主机路径 | 用途 |
| --- | --- |
| `data/zerotier/dist/` | 导出的 `planet` / `moon` 文件 |
| `data/zerotier/ztncui/` | 管理界面配置与登录数据 |
| `data/zerotier/one/` | ZeroTier 身份与控制器数据 |
| `data/zerotier/config/` | 生成 Planet 所需的配置和密钥 |

**更新前先备份。**运行 `./deploy.sh` 并选择“更新”会保留已挂载的数据，但会重建容器；选择重新“安装”前要特别注意数据清理提示，不能把它当作无损升级。部署脚本在数据目录已有内容时不会自动重新生成 `planet` / `moon`；**只修改 IP 或端口环境变量，不会更新已生成的节点信息和客户端文件。**

### 保护管理界面和下载入口

- 首次登录立即修改默认密码；管理界面默认使用 `http://`，`3443` 只是端口号，**不表示已启用 TLS**。
- 使用防火墙限制管理端口的访问来源；对外提供管理界面时，建议由 Nginx 等反向代理终止 HTTPS。
- 下载链接和相关密钥不要公开传播。文件服务使用 `SECRET_KEY` 作为下载密钥；如果没有固定该值，容器重启后会生成新密钥，旧下载链接随之失效。镜像中的 `FILE_KEY` **不是**文件服务实际读取的变量。

以下示例假设 Nginx 与容器运行在同一台主机，证书已自行准备，且 `3443` 是实际映射的管理端口。还应通过防火墙限制对 `3443` 的直接公网访问：

```nginx
server {
    listen 80;
    server_name planet.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name planet.example.com;

    ssl_certificate /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:3443;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 使用 Docker Compose（手动方式）

仓库**没有附带** `compose.yaml`。如果不使用交互式部署脚本，可将以下示例保存为 `compose.yaml`，填入自己的公网 IPv4 和足够长的随机 `SECRET_KEY` 后，在该文件所在目录运行 `docker compose up -d`：

```yaml
services:
  myztplanet:
    image: xubiaolin/zerotier-planet:latest
    container_name: myztplanet
    restart: unless-stopped
    ports:
      - "9994:9994/tcp"
      - "9994:9994/udp"
      - "3443:3443/tcp"
      - "3000:3000/tcp"
    environment:
      IP_ADDR4: "203.0.113.10" # 替换为服务器公网 IPv4
      IP_ADDR6: "" # 留空时容器仍会尝试自动获取公网 IPv6
      ZT_PORT: "9994"
      API_PORT: "3443"
      FILE_SERVER_PORT: "3000"
      SECRET_KEY: "replace-with-a-long-random-secret"
    volumes:
      - ./data/zerotier/dist:/app/dist
      - ./data/zerotier/ztncui:/app/ztncui
      - ./data/zerotier/one:/var/lib/zerotier-one
      - ./data/zerotier/config:/app/config
```

> 示例端口与容器环境变量保持一致；如果修改监听端口，请同步修改映射和防火墙规则。**不要把填有真实公网 IP、下载密钥或私密配置的 Compose 文件提交到公开仓库。**手动 Compose 部署不提供 `deploy.sh` 的交互流程，遇到问题请检查 `docker logs myztplanet`。

### 卸载

在项目目录运行 `./deploy.sh`，根据菜单提示选择“卸载”。若手动管理容器，可执行 `docker rm -f myztplanet`；**这只删除容器，不等于清除宿主机的 `data/zerotier/` 数据**。删除数据前请先核实目录内容并完成备份。

## 常见问题

### 为什么无法连接自建 Planet？

先核对客户端是否使用**当前部署生成的** `planet` 并已重启 ZeroTier；再检查服务器公网 IP，以及 `9994/tcp`、`9994/udp` 的容器端口映射、服务器防火墙和云平台安全组。自定义过端口时，以实际配置为准。

### 已加入网络，为什么仍 ping 不通其他设备？

确认两端都已加入**同一个 Network ID**、在管理界面获得授权并分配了地址；随后检查目标设备操作系统防火墙是否允许 ICMP 和所需业务端口。不能仅凭 `join OK` 判断网络已经可用。

### 如何判断直连还是中转？

在客户端运行 `zerotier-cli peers`，查看目标节点对应的连接状态。`DIRECT` 表示该条连接直连，`RELAY` 表示该条连接经中转；连接到 Planet 为 `DIRECT` 并不保证到其他 LEAF 也直连。

### 为什么看不到 ZeroTier 官方 Planet？

客户端替换为本项目生成的 `planet` 后，根节点列表指向自建 Planet，不会同时显示官方 Planet。请确认使用该文件是你的预期操作。

### 服务器公网 IP 或通信端口变了怎么办？

备份整个 `data/zerotier/` 后重新规划部署，并生成与新地址相符的 `planet` 文件，然后重新分发给客户端。已有数据非空时，**仅重启容器或改环境变量不会重生成文件**；重新安装可能删除旧数据和身份，操作前务必备份。

### 忘记管理密码怎么办？

在项目目录运行 `./deploy.sh`，选择菜单中的“重置密码”。脚本会将管理界面密码恢复为默认值 `password` 并重启容器；登录后立即更换密码。不要为重置密码删除 `data/zerotier/`，其中还保存着节点和网络数据。

### 支持域名或 ARM 服务器吗？

管理界面可以通过域名与反向代理访问；Planet 生成逻辑使用 `IP_ADDR4` / `IP_ADDR6` 填写节点地址，不能简单用域名替代 IP。镜像构建脚本包含 `linux/arm64` 和 `linux/amd64`，使用前请确认所拉取的镜像包含对应架构。

### PVE LXC 容器内没有创建虚拟网卡怎么办？

ZeroTier 需要访问 TUN 设备。请按当前 Proxmox / LXC 版本核对容器的 TUN 设备映射、权限和网络配置；修改特权模式或放宽设备权限会改变安全边界，不建议在不了解影响时直接套用旧版配置片段。

## 项目与社区

### 开发计划

- [ ] 多 Planet 支持
- [x] 自定义管理界面端口
- [ ] Planet 与 Controller 分离部署

### 风险声明

本项目用于学习和研究。自行部署需要维护服务器、凭据和客户端配置；请评估安全与可用性风险，并遵守适用的法律及服务条款。项目维护者不对使用本项目产生的损失承担责任。

### 致谢

感谢以下支持项目的朋友（按原名单顺序）：

随性、我、你好、Calvin、小猪猪的饲养员、情若犹在、天天星期天、啊乐、夏末秋至、\*\*忠、岸芷汀兰、Kimi Chen、匿名、阳光报告旷课、濂溪先生、Water、匿名、匿名、陆、精钢葫芦娃、唯、王小新、匿名、Duck不必。

### 相关项目与参考资料

- [WireGuard 一键脚本](https://github.com/xubiaolin/wireguard-onekey)
- [ZeroTier 虚拟局域网详解](https://www.glimmer.ltd/2021/3299983056/)
- [五分钟自建 ZeroTier 的 Planet / Controller](https://v2ex.com/t/799623)
