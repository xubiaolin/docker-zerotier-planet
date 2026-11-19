# 审计整改工单

## Notes

[规格](spec.md)覆盖 14 项审计发现。双架构发布与独立发布脚本两项合并为工单 06。

## Decisions-so-far

- [01 阻止登录异常中断 ZeroTier](issues/01-admin-login-isolation.md)
- [02 收紧管理端口与管理员凭据](issues/02-management-access.md)
- [03 升级沿用宿主机端口绑定](issues/03-preserve-published-ports.md)
- [04 修复首装端口冲突和就绪判断](issues/04-retry-first-install.md)
- [05 恢复原状态后结束回滚](issues/05-finish-rollback.md)
- [06 将双架构验证与正式发布串联](issues/06-verified-release.md)
- [07 镜像包含上游许可证和声明](issues/07-license-notices.md)
- [08 拒绝无法通告的 IPv6 地址](issues/08-validate-endpoints.md)
- [09 修复 Docker 组管理员的数据维护](issues/09-data-permissions.md)
- [10 兼容旧配置的前导零端口](issues/10-legacy-port-values.md)
- [11 限定签名文件健康检查范围](issues/11-healthcheck-artifacts.md)
- [12 锁定管理界面构建依赖](issues/12-lock-ui-dependencies.md)
- [13 移除旧内核升级菜单](issues/13-remove-kernel-menu.md)

## Fog

新版 ARM64 运行需通过 GitHub 托管运行器验收。正式 Docker Hub 发布取决于维护者确认上游分发权和发布凭据。
