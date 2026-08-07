# 架构说明

项目保持单容器部署，但内部按职责分层：

```text
deploy.sh / compose.yaml
        |
        v
container/entrypoint.sh
  |-- 配置解析与校验
  |-- 身份、Planet/Moon、ztncui 初始化
  `-- supervisord
       |-- zerotier-one
       |-- ztncui
       `-- 受限文件服务
```

## 数据所有权

| 容器路径 | 所有者 | 内容 |
| --- | --- | --- |
| `/var/lib/zerotier-one` | ZeroTier | 身份、控制器数据库、签名材料 |
| `/app/config` | 运行时 | 端口、IP、下载密钥 |
| `/app/dist` | 运行时 | 对客户端分发的 Planet/Moon |
| `/app/ztncui/state` | ztncui | 用户和界面状态 |

镜像内的 ZeroTier 二进制和 ztncui 源码是不可变构建产物，不从数据卷执行。可写状态全部位于声明的数据卷中。

## 初始化状态机

启动过程先解析所有配置并验证端口与不可变端点。随后：

1. 复用或生成文件下载密钥；
2. 复用或生成 ZeroTier 身份；
3. 缺少产物时，使用官方 `zerotier-idtool` 生成 Moon 和 Earth Planet；
4. 持久化验证后的配置；
5. 迁移或初始化 ztncui 状态；
6. 启动三个受监督进程。

所有配置文件和生成产物都通过临时文件再原子替换。重启不会轮换身份、下载密钥或管理员密码。

## 上游版本

ZeroTier 使用正式 Tag，由发布工作流自动检测。ztncui 没有正式 Tag，因此固定到经测试的 Commit，并使用本项目保存的 npm lockfile 构建。
