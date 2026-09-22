# 测试验证记录

本目录用于记录 Categraf Chart / Operator 在测试环境中的实际验证结果。

## 记录格式

每条记录至少包含：

1. 测试日期、测试人、变更范围。
2. 测试环境：Flashcat、Kubernetes、节点、操作系统、容器运行时和 Helm 版本。
3. 被测产物：Chart/Operator 版本、镜像、包 SHA256、OCI Digest。
4. 测试步骤与每步结果。
5. 已知限制、影响面和回滚方式。
6. 不在文档中记录密码、Token、Secret 明文。
