Status: resolved
Type: task

# 阻止登录异常中断 ZeroTier

审计 1。验证表单字段并将登录路由的异步错误交给 Express。验证正常登录及后端报错时 Web 和 ZeroTier 的状态。

[规格](../spec.md)

## Answer

ztncui 交给 Express 处理登录异常。端到端测试用正常登录验证后台凭据暂不可读时返回 500，ZeroTier 与下载检查仍通过，恢复文件后可再次登录。

## Comments
