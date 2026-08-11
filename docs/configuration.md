# 配置参考

Compose 默认读取项目根目录的 `.env`。容器解析配置的优先级为：显式环境变量、持久化配置文件、安全默认值。

| 变量 | 默认值 | 持久化文件 | 说明 |
| --- | --- | --- | --- |
| `DOCKER_IMAGE` | `xubiaolin/zerotier-planet:latest` | — | Compose 使用的镜像 |
| `CONTAINER_NAME` | `myztplanet` | — | 容器名称 |
| `DATA_DIR` | `./data/zerotier` | — | 宿主机数据目录 |
| `ZT_PORT` | `9994` | `config/zerotier-one.port` | Planet TCP/UDP 端口 |
| `API_PORT` | `3443` | `config/ztncui.port` | ztncui HTTP 端口 |
| `FILE_SERVER_PORT` | `3000` | `config/file_server.port` | 文件下载端口 |
| `IP_ADDR4` | 自动探测 | `config/ip_addr4` | Planet 公网 IPv4 |
| `IP_ADDR6` | 自动探测 | `config/ip_addr6` | Planet 公网 IPv6，可为空 |
| `ZTNCUI_ADMIN_PASSWORD` | 随机生成 | ztncui `passwd` | 只影响首次初始化 |

三个端口必须处于 `1-65535` 且互不相同。至少需要一个公网地址。
`DATA_DIR` 不能指向文件系统根、项目目录或项目的上级目录；请始终使用专用子目录。

直接使用 Compose 时，首次生成的管理密码保存在 `config/ztncui.initial-password`；读取并登录后应删除该明文文件。`deploy.sh install` 会显示一次并自动删除它。

`deploy.sh install` 完成时和 `deploy.sh status` 会优先读取上述持久化文件，因此自动探测得到的真实 IP 和实际运行端口也会出现在管理地址与下载 URL 中，而不是使用 `.env` 中的空值或占位符。IPv6 URL 会自动使用方括号格式。

`ZT_PORT`、`IP_ADDR4` 和 `IP_ADDR6` 会进入签名后的 Planet/Moon。已初始化后修改这些值，普通启动会拒绝继续；编辑 `.env` 后运行：

```bash
./deploy.sh reconfigure
```

该命令会先备份数据，再使用原有 ZeroTier 身份重新生成产物。

## 敏感配置

以下内容不应提交到 Git：

- `.env` 中显式设置的管理员密码；
- `data/zerotier/config/file_server.key`；
- `data/zerotier/one/authtoken.secret`；
- `data/zerotier/one/identity.secret`；
- `moon.json`、`planet.json` 中的签名私钥。

容器会把这些文件限制为所有者可读。备份也应按秘密材料保护。
