# 安全建议

## 凭据

新安装生成随机 ztncui 管理密码，部署脚本只显示一次。立即登录并按组织策略更新密码。

文件下载服务使用独立的持久密钥。推荐使用请求头：

```bash
curl -H "Authorization: Bearer $KEY" http://SERVER:3000/planet -o planet
```

兼容的 `?key=` 形式可能进入浏览器历史、代理日志或聊天记录，应只在受控环境使用。

## 网络暴露

- 对客户端开放 Planet TCP/UDP 端口。
- 管理界面和文件服务应通过防火墙限制来源。
- 如需 TLS，请在容器外使用受维护的反向代理。
- 不要把 ZeroTier 本地管理 API 端口直接暴露到公网。

## 文件服务限制

文件服务只接受 `GET` 和 `HEAD`，只提供 `planet` 与规范的十六进制 `.moon` 文件，拒绝符号链接和其他路径，并对密钥使用固定长度摘要比较。

## 容器权限

Compose 默认启用只读根文件系统和 `no-new-privileges`。ztncui 与文件服务以非 root 用户运行；ZeroTier 服务保留自身运行所需权限。不要为了排错长期使用 `--privileged`。

## 供应链

- ZeroTier 构建固定到解析后的正式 Tag 和 Commit；
- ztncui 固定 Commit 与 npm lockfile；
- 发布镜像包含 OCI 版本信息、SBOM 和 provenance；
- `latest` 只在全部测试通过后更新。

ztncui 上游依赖较旧，当前锁文件仍包含 npm 报告的高、中等级公告。镜像构建会阻断 critical 等级问题，但管理界面仍应限制为可信来源访问；彻底消除这些公告需要独立完成 ztncui API 与前端兼容升级。
