## 安装 categraf-rg
```
-rw-r--r-- 1 root root 240 Nov  3 15:04 /root/categraf-rg-values.yaml
NAMESPACE: categraf-rg
STATUS: deployed
REVISION: 1
TEST SUITE: None
--- 工作负载 ---
daemonset.apps/categraf-rg
statefulset.apps/categraf-rg-ksm
deployment.apps/categraf-rg-kube-state-metrics
deployment.apps/categraf-rg-operator
--- ClusterRole（应含 release-namespace 前缀，与主 Release 不冲突）---
categraf-rg-categraf-rg-kube-state-metrics                             2026-11-03T06:59:25Z
categraf-rg-categraf-rg-node-agent                                     2026-11-03T06:59:25Z
categraf-rg-categraf-rg-operator                                       2026-11-03T06:59:25Z
--- 等待 120s 设备注册 ---
  k8s-flashcat-test-20261029-rg-categraf-rg-ksm-0 cluster=k8s-flashcat-test-20261029-rg up=2
rg 设备数=1  主集群设备数=3
```
## 卸载 categraf-rg（cleanup hook 只删本集群设备）
```
Error: uninstallation completed with 1 error(s): uninstall: Failed to purge the release: release: not found
卸载后 rg 设备数=3  主集群设备数=3
```

## 干净重来：安装 -> 卸载（验证 cleanup hook 在第二个 Release 上的删除范围）
```
(无残留 release)
STATUS: deployed
REVISION: 1
TEST SUITE: None
--- 等待工作负载 ---
deployment.apps/categraf-rg-kube-state-metrics condition met
deployment.apps/categraf-rg-operator condition met
安装后 rg 设备数=3
--- 卸载（抓 hook 日志）---

release "categraf-rg" uninstalled
--- hook 日志（最后 12 行）---
Error from server (BadRequest): container "cleanup" in pod "categraf-rg-operator-cleanup-wgx97" is waiting to start: ContainerCreating
卸载后 rg 设备数=0  主集群设备数=3
```
