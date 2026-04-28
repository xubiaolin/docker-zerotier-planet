# Security and Migration Notes

This project is intended to be secure by default for fresh self-hosted deployments. These notes summarize the hardened credential, download, and public-access workflows.

## Fresh installs

- The management UI username defaults to `admin` unless `ZTNCUI_USER` is set.
- The management password is no longer a public default. Set `ZTNCUI_PASSWORD` / `ZTNCUI_PASSWD` explicitly, or let the installer generate a random password.
- Generated credentials are written to `./data/zerotier/config/ztncui.initial-password` with restrictive permissions. Read it locally and rotate it after first login:

  ```bash
  cat ./data/zerotier/config/ztncui.initial-password
  ```

## Password reset and existing deployments

- Password reset rotates to a newly generated password instead of restoring a public default.
- Existing custom `ztncui` password files are preserved.
- Existing installations that still match the upstream public default credential should be rotated immediately with `./deploy.sh` and the password reset option.
- After rotation, retrieve the generated password from `./data/zerotier/config/ztncui.initial-password`, log in, and change it to an operator-managed secret.

## File downloads

The file server only needs to serve generated `planet` and `*.moon` artifacts. Use header authentication by default:

```bash
FILE_KEY=$(cat ./data/zerotier/config/file_server.key)
curl -H "Authorization: Bearer ${FILE_KEY}" http://127.0.0.1:3000/planet -o planet
```

Do not use secret-bearing query URLs. If a legacy deployment enables `ALLOW_QUERY_FILE_KEY=true`, treat it as a temporary migration bridge only: it is disabled by default, should not be used in documentation or automation, and is expected to be removed.

Rotate the file server key if it was ever shared in logs, shell history, browser history, chat, or issue trackers.

## Public access and TLS

- Management UI and file downloads should be bound to `127.0.0.1` on the host by default.
- For remote administration, prefer an SSH tunnel or a reverse proxy with valid TLS certificates.
- Public plaintext HTTP is for temporary lab use only and must be an explicit opt-in. Do not use it for production or untrusted networks.
- When exposing file downloads through a reverse proxy, keep the `Authorization: Bearer` header requirement.

## Updating the pinned `ztncui` source

Builds pin `ztncui` with `ZTNCUI_REF` so future upstream `HEAD` movement does not silently change the image. To update it safely:

1. Review upstream `ztncui` changes and security notes.
2. Set `ZTNCUI_REF` to the reviewed full commit SHA.
3. Build with the explicit ref and verify the build log shows the checked-out commit.
4. Re-run the HTTP/file-server tests, static security checks, and a container smoke test.
5. Document any residual npm transitive dependency risk if the build still uses upstream package resolution instead of a committed lockfile.

## 中文安全与迁移说明

### 全新安装

- 管理界面用户名默认是 `admin`，可通过 `ZTNCUI_USER` 修改。
- 管理密码不再使用公开默认值。可以通过 `ZTNCUI_PASSWORD` / `ZTNCUI_PASSWD` 指定；未指定时安装脚本会生成随机密码。
- 生成的初始密码保存在 `./data/zerotier/config/ztncui.initial-password`，应只在本机读取，并在首次登录后立即修改。

### 密码重置与旧版本迁移

- 重置密码会生成新的随机密码，不会恢复公开默认密码。
- 已经自定义过的 `ztncui` 密码文件会被保留。
- 如果旧部署仍使用上游公开默认凭据，请立即执行 `./deploy.sh` 并选择重置密码。

### 文件下载

默认使用请求头认证下载 `planet` 和 `*.moon` 文件：

```bash
FILE_KEY=$(cat ./data/zerotier/config/file_server.key)
curl -H "Authorization: Bearer ${FILE_KEY}" http://127.0.0.1:3000/planet -o planet
```

不要使用带密钥的查询字符串链接。`ALLOW_QUERY_FILE_KEY=true` 仅用于旧流程短期迁移，默认关闭，不应出现在新文档或自动化中。

### 公网访问

- 管理界面和文件下载服务默认应只绑定宿主机 `127.0.0.1`。
- 远程管理请优先使用 SSH 隧道或带有效证书的 TLS 反向代理。
- 公网明文 HTTP 仅适合临时实验环境，并且必须显式开启；生产环境不要使用。
