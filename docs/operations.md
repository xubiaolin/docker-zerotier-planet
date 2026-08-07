# 运维指南

## 状态与日志

```bash
./deploy.sh status
./deploy.sh doctor
./deploy.sh logs
```

健康检查同时验证 ZeroTier 本地 API、ztncui 和文件服务。日志只写入容器标准输出，不在数据目录维护独立日志文件。

## 升级与回滚

```bash
./deploy.sh upgrade
```

升级流程：

1. 将当前镜像保存为本地回滚标签；
2. 在旧服务仍运行时拉取新镜像；
3. 停止旧服务，并把数据打包到数据目录旁的 `.zerotier-planet-backups/`；
4. 启动新镜像；
5. 等待健康检查；
6. 失败时恢复旧镜像。

如需固定版本，在 `.env` 中设置：

```dotenv
DOCKER_IMAGE=xubiaolin/zerotier-planet:1.16.2
```

然后执行 `docker compose up -d`。不可变发布标签还包含本项目 Git Commit。

## 手动备份

至少备份整个 `DATA_DIR`。最重要的内容是：

- `one/identity.secret` 与 `one/identity.public`；
- `one/moon.json` 与 `one/planet.json`；
- `one/controller.d/`；
- `config/`；
- `ztncui/state/etc/`；
- `dist/`。

恢复时先停止容器，将完整备份还原到原路径，再启动服务。不要只生成一套新身份后覆盖旧的控制器数据库。

## 修改公网地址或 Planet 端口

编辑 `.env` 后运行：

```bash
./deploy.sh reconfigure
```

该流程保留原有身份与签名材料，仅重新签名 Planet/Moon 产物。客户端需要重新分发新的 `planet` 文件。

## 密码与下载密钥

```bash
./deploy.sh reset-password
```

下载密钥在首次初始化后保持不变。若必须轮换，可停止容器、替换 `config/file_server.key`，设置权限为 `0600`，然后重启。

## 卸载

```bash
./deploy.sh uninstall
```

该命令删除容器但保留数据。`purge --yes-i-understand` 会把数据移动到带时间戳的隔离目录，仍可手动恢复。
