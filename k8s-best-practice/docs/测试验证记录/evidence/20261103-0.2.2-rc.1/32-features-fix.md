# CMD: G4 修正轮：指标消失/存在改用短窗口（60s/45s）+ 足够长的观察时间；修正 C3 grep 与 C9 设备等待
# AT: 2026-11-03T06:28:30Z / 2026-11-03T14:28:30+0800

## C3-fix extraScrapeConfigs
```
9:  - job_name: 'kube-state-metrics'
16:  - job_name: 'app-metrics'
56:  - job_name: customer-custom-job
58:    - namespaces:
71:  - job_name: 'coredns'
78:  - job_name: 'calico'
89:  - job_name: 'cilium'
up{job=customer-custom-job} = 1
```
## C4-fix annotation path 生效性
```
改前 up{job=app-metrics} 值集合 = [1]  up=1 数量=1

改坏后 up 值集合 = [0]  up=1 数量=0

恢复后 up 值集合 = [1]  up=1 数量=1
```
## C5-fix inputs 关闭（观察 130s 后用 60s 短窗口判定）
```
60s 内 up{job=kubelet} series      = 0
60s 内 node_cpu_seconds_total      = 0
60s 内 disk_used                   = 0
```
## C6-fix 组件组合（观察 130s 后用 60s 短窗口判定）
```
60s 内 up{job=coredns}            = 0
60s 内 up{job=kube-proxy}         = 0
60s 内 up{job=kube-state-metrics} = 0
up{job=apiserver}                 = []
up{job=kube-controller-manager}   = [0]
up{job=kube-scheduler}            = [0]
up{job=etcd}                      = [0]
```
## C7-fix kubeStateMetrics.enabled=false
```
(KSM Deployment 已移除)
60s 内 up{job=kube-state-metrics} = 0
60s 内 kube_pod_info              = 15
```
## C9 多 Release 隔离（重测）
```
Release "categraf-rg" does not exist. Installing it now.
Error: open /root/categraf-rg-values.yaml: no such file or directory
--- 资源命名隔离 ---

--- ClusterRole 隔离 ---

--- 等待 90s 设备注册 ---
--- 主集群设备 ---
  k8s-flashcat-test-20261029-categraf-ksm-0 up=2
  k8s-node1 up=2
  k8s-node2 up=2
```
### C9 卸载
```
Error: uninstall: Release not loaded: categraf-rg: release: not found
rg 设备数=0  主集群=3
```

## C7f 更正（诚实记录）：该断言未通过，原因未定位，列为待复核
```
本集群 60s 内 kube_pod_info series = 38
全库 kube_pod_info series（对照：其它环境也有 KSM，未过滤会误判） = 38
```
```
复核：全库与带 cluster 过滤的 series 数一致（其它环境并不上报 kube_pod_info），说明首轮 FAIL 不是“未加过滤”造成；也无法用“KSM Pod 终止耗时/VM 写入延迟”完全解释（观察点已过 130s）。因此 **C7f-kube_pod_info 停止上报 不作为通过项，列入“待复核”**，不据此判定 Chart 缺陷。
已通过的相关项：KSM Deployment/Service 被移除、up{job="kube-state-metrics"} 掉线（C7f 前两条）。
```
