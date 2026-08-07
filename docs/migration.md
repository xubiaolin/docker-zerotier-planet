# 从旧版迁移

新版本继续使用默认宿主机目录 `data/zerotier`，并兼容以下旧数据：

- `config/` 中的端口、IP 与文件下载密钥；
- `one/` 中的 ZeroTier 身份、控制器数据库和世界签名材料；
- `dist/` 中已生成的 Planet/Moon；
- `ztncui/src/etc/` 中的用户和网络界面状态。

启动时，旧的 `ztncui/src/etc/` 会复制到新的 `ztncui/state/etc/`。旧目录不会被删除，已有管理密码不会重置。

## 推荐步骤

1. 停止旧容器，但不要删除 `data/zerotier`。
2. 复制整个数据目录到独立备份位置。
3. 更新代码。
4. 如果原来使用非默认端口或 IP，把它们写入 `.env`；`./deploy.sh install` 会优先导入旧配置。
5. 运行 `./deploy.sh doctor`。
6. 运行 `./deploy.sh install`。
7. 确认管理界面、已有网络、Planet/Moon 下载和客户端连接。

## 重要变化

- 不再编译或运行 `mkworld_custom.cpp`。
- Planet 使用当前 ZeroTier 官方 `zerotier-idtool genmoon` 生成。
- 容器镜像不再从持久化卷执行旧版 ZeroTier 或 ztncui 源码。
- 默认管理员密码只对旧安装保留；新安装使用随机密码。
- 安装命令不再删除数据，也不会修改内核、软件源或 Docker daemon。

如果新容器未通过健康检查，保留原数据并重新使用旧镜像即可回滚。
