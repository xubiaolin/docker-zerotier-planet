Status: resolved
Type: task

# 修复 Docker 组管理员的数据维护

审计 9。从只读容器读取原配置。普通 Docker 管理员确认后可以删除已核实的部署数据。

[规格](../spec.md)

## Answer

首次参数由镜像的只读文件探测读取。删除按部署路径和挂载布局进行，容器测试验证 Docker 组管理员可处理 root 文件并保留备份。

## Comments
