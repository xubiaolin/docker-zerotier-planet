Status: resolved
Type: task

# 限定签名文件健康检查范围

审计 11。探测当前节点对应的 Planet 和 Moon，忽略其他导出文件。

[规格](../spec.md)

## Answer

健康检查读取当前节点 ID，只探测对应的 Moon 和 Planet。临时放入无关空文件时检查仍通过，移除当前节点的产物时检查失败。

## Comments
