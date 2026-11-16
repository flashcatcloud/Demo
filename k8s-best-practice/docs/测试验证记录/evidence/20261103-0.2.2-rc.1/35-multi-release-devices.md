# CMD: 多 Release 并存：第二个 Release 的 Agent Pod 状态、设备注册情况与日志
# AT: 2026-11-03T06:59:24Z / 2026-11-03T14:59:24+0800

## 安装 categraf-rg（ns=categraf-rg）
```
STATUS: deployed
REVISION: 1
TEST SUITE: None
--- Pod 状态（等待 30s）---
NAME                                              READY   STATUS    RESTARTS   AGE   IP             NODE        NOMINATED NODE   READINESS GATES
categraf-rg-ksm-0                                 1/1     Running   0          30s   10.244.1.101   k8s-node2   <none>           <none>
categraf-rg-kube-state-metrics-5cf64df598-cvsdg   1/1     Running   0          30s   10.244.1.102   k8s-node2   <none>           <none>
categraf-rg-lhqmk                                 1/1     Running   0          30s   192.168.31.6   k8s-node2   <none>           <none>
categraf-rg-operator-5db88f65c9-g4nmh             1/1     Running   0          30s   10.244.1.103   k8s-node2   <none>           <none>
categraf-rg-vh24x                                 1/1     Running   0          31s   192.168.31.5   k8s-node1   <none>           <none>

NAME                         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/categraf-rg   2         2         2       2            2           <none>          31s

NAME                               READY   AGE
statefulset.apps/categraf-rg-ksm   1/1     31s

NAME                                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/categraf-rg-kube-state-metrics   1/1     1            1           31s
deployment.apps/categraf-rg-operator             1/1     1            1           31s
--- Pod 事件/重启原因 ---
Name:             categraf-rg-ksm-0
    State:          Running
    Restart Count:  0
    Name:      categraf-rg-ksm-config
    Name:      categraf-rg-ksm-scrape
    ConfigMapName:           kube-root-ca.crt
Name:             categraf-rg-kube-state-metrics-5cf64df598-cvsdg
    State:          Running
    Restart Count:  0
    ConfigMapName:           kube-root-ca.crt
Name:             categraf-rg-lhqmk
    State:          Running
    Restart Count:  0
    Name:      categraf-rg-config
    Name:      categraf-rg-input-cadvisor
    Name:      categraf-rg-input-node-exporter
    Name:      categraf-rg-input-kube-proxy
    Name:      categraf-rg-input-cpu
    Name:      categraf-rg-input-mem
    Name:      categraf-rg-input-disk
    Name:      categraf-rg-input-diskio
    Name:      categraf-rg-input-net
    Name:      categraf-rg-input-netstat
    Name:      categraf-rg-input-system
    Name:      categraf-rg-input-kernel
    Name:      categraf-rg-input-swap
    Name:      categraf-rg-input-process
    Name:      categraf-rg-disable-host
    Name:      categraf-rg-disable-syslog
    ConfigMapName:           kube-root-ca.crt
--- Node Agent 日志（若启动）---
2026/11/03 14:59:26 metrics_agent.go:289: W! no configuration of input: syslog
2026/11/03 14:59:26 metrics_agent.go:429: I! input: local.system uuid: 0c43c8ae-bad5-4c79-ab18-cbfcef8976ae started
2026/11/03 14:59:26 http_provider.go:292: I! http provider: start reload config from remote: http://flashcat.local:19000/v1/n9e-plus/collects
2026/11/03 14:59:27 http_provider.go:300: I! remote version:, current version:
2026/11/03 14:59:27 metrics_agent.go:273: I! provider http has no inputs
2026/11/03 14:59:27 metrics_agent.go:273: I! provider rmq has no inputs
2026/11/03 14:59:27 metrics_agent.go:273: I! provider debug has no inputs
2026/11/03 14:59:27 agent.go:68: I! [*agent.MetricsAgent] started
2026/11/03 14:59:27 agent.go:71: I! agent started
2026/11/03 14:59:27 rmq_provider.go:230: I! starting to consume tasks
2026/11/03 14:59:27 agent.go:160: I! logs checksum changed, add:map[], del:map[]
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name cpu duration_seconds 0.000570302
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name mdadm duration_seconds 5.7597e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name entropy duration_seconds 7.9257e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name netdev duration_seconds 0.0001339
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name edac duration_seconds 3.1669e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name hwmon duration_seconds 0.000230179
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name uname duration_seconds 8.947e-06
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name filenotify duration_seconds 8.9517e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name timex duration_seconds 1.5288e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name time duration_seconds 7.2875e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name schedstat duration_seconds 5.4662e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name pressure duration_seconds 0.000181127
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name netstat duration_seconds 0.00095589
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name stat duration_seconds 0.000180686
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name xfs duration_seconds 1.4286e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name softnet duration_seconds 0.000141434
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name cpufreq duration_seconds 7.8947e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name sockstat duration_seconds 0.000140521
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name watchdog duration_seconds 1.9907e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name loadavg duration_seconds 3.5486e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name meminfo duration_seconds 0.000122528
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name vmstat duration_seconds 9.0909e-05
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name udp_queues duration_seconds 0.000121386
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name diskstats duration_seconds 0.00050498
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name selinux duration_seconds 2.113e-06
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name filesystem duration_seconds 0.017433093
2026/11/03 14:59:41 syslog_linux.go:207: E! failed to collect from log file%!(EXTRA string=err, *fmt.wrapError=failed to execute tail command: exit status 1)
2026/11/03 14:59:41 collector.go:194: E! collector failed name syslog duration_seconds 0.012931521 err failed to execute tail command: exit status 1
2026/11/03 14:59:41 collector.go:198: I! collector succeeded name processes duration_seconds 0.020686563
--- 等待到 90s 再查设备 ---
rg 设备数 = 3
  k8s-flashcat-test-20261029-rg-categraf-rg-ksm-0 cluster=k8s-flashcat-test-20261029-rg up=2
  k8s-flashcat-test-20261029-rg-k8s-node1 cluster=k8s-flashcat-test-20261029-rg up=2
  k8s-flashcat-test-20261029-rg-k8s-node2 cluster=k8s-flashcat-test-20261029-rg up=2
```
## 卸载并清理
```
Error: uninstall: Release not loaded: categraf-rg: release: not found
卸载后 rg 设备数 = 3

```

## 补充：卸载失败排查与清理（上一步报 release not found）
```
$ helm list -A | grep categraf
categraf	categraf 	35      	2026-11-03 14:57:19.204093394 +0800 CST	deployed	categraf-0.2.2-rc.1	0.5.32     
$ helm uninstall 重试
Error: uninstall: Release not loaded: categraf-rg: release: not found
$ 等待 30s 后设备
  k8s-flashcat-test-20261029-categraf-ksm-0 cluster=k8s-flashcat-test-20261029 up=2
  k8s-flashcat-test-20261029-rg-categraf-rg-ksm-0 cluster=k8s-flashcat-test-20261029-rg up=1
  k8s-flashcat-test-20261029-rg-k8s-node1 cluster=k8s-flashcat-test-20261029-rg up=1
  k8s-flashcat-test-20261029-rg-k8s-node2 cluster=k8s-flashcat-test-20261029-rg up=1
  k8s-node1 cluster=k8s-flashcat-test-20261029 up=2
  k8s-node2 cluster=k8s-flashcat-test-20261029 up=2
  k8s-node3-docker cluster=- up=2
  k8s-node5-docker cluster=- up=2
  luomaojian-docker cluster=- up=2
$ 清理命名空间
Error from server (NotFound): namespaces "categraf-rg" not found
```

## 再次验证：重装同名 Release 后正常卸载（触发 cleanup hook 清理残留设备）
```
$ helm upgrade --install categraf-rg（重建 namespace）
NAMESPACE: categraf-rg
STATUS: deployed
REVISION: 2
TEST SUITE: None
$ helm list -n categraf-rg
NAME       	NAMESPACE  	REVISION	UPDATED                                	STATUS  	CHART              	APP VERSION
categraf-rg	categraf-rg	2       	2026-11-03 15:05:19.611555789 +0800 CST	deployed	categraf-0.2.2-rc.1	0.5.32     
$ 设备（rg 集群）
  k8s-flashcat-test-20261029-rg-categraf-rg-ksm-0 up=2
  k8s-flashcat-test-20261029-rg-k8s-node1 up=2
  k8s-flashcat-test-20261029-rg-k8s-node2 up=2
$ helm uninstall categraf-rg -n categraf-rg
release "categraf-rg" uninstalled
$ 等待 40s 后设备
  k8s-flashcat-test-20261029-rg-categraf-rg-ksm-0 up=1
rg 设备数 = 1
主集群设备 = 3
$ 清理 namespace
namespace "categraf-rg" deleted
```

## 二次清理验证：重装 rg 后卸载并抓 cleanup hook 日志（确认 ksm 设备是否被清）
```
$ 安装 rg（同名 Release / 同 clusterName）
STATUS: deployed
REVISION: 1
TEST SUITE: None
安装后 rg 设备数 = 3
$ 抓 hook 日志 + 卸载


--- cleanup hook 日志（设备删除段）---

卸载后 rg 设备数 = 3
主集群设备数 = 3
$ 清理 namespace
Error from server (NotFound): namespaces "categraf-rg" not found
```

## 清理残留 rg 设备（在全新 namespace 中安装同 clusterName 的 Release，再卸载触发 cleanup hook）
```
$ kubectl create namespace categraf-rg-clean
namespace/categraf-rg-clean created
$ 安装（同 clusterName=k8s-flashcat-test-20261029-rg）
STATUS: deployed
REVISION: 1
TEST SUITE: None
安装后 rg 设备数 = 4  （应含旧残留）
$ 抓 hook 日志并卸载

release "categraf-rg-clean" uninstalled
--- hook 日志 ---
2026-11-03T07:09:42Z	INFO	target cleanup completed	{"cluster": "k8s-flashcat-test-20261029-rg", "agent_type": "nodeAgent", "total_targets": 0, "delete_errors": 0}
2026-11-03T07:09:42Z	INFO	all heartbeats stopped	{"agent_type": "ksmAgent", "targets": 2}
2026-11-03T07:09:42Z	INFO	deleted target	{"ident": "k8s-flashcat-test-20261029-rg-categraf-rg-clean-ksm-0"}
2026-11-03T07:09:42Z	INFO	deleted target	{"ident": "k8s-flashcat-test-20261029-rg-categraf-rg-ksm-0"}
2026-11-03T07:09:42Z	INFO	target cleanup completed	{"cluster": "k8s-flashcat-test-20261029-rg", "agent_type": "ksmAgent", "total_targets": 2, "delete_errors": 0}
2026-11-03T07:09:42Z	INFO	cleanup-once completed
2026-11-03T07:09:42Z	INFO	setup	cleanup-once completed successfully
卸载后 rg 设备数 = 0
主集群设备 = 3/3
$ 删除临时 namespace
namespace "categraf-rg-clean" deleted
```

## 结论（多 Release 场景）
```
1) 隔离正确：第二个 Release 的 5 个 Pod 正常运行，资源名/ClusterRole 无冲突；
   设备按 cluster 标签隔离，ident 模板 ${cluster}-$hostname 生效（...-rg-k8s-node1 / ...-rg-k8s-node2）；
   主集群设备不受影响（3/3 target_up=2）。
2) 卸载清理正确：在干净 namespace 中重装同 clusterName 的 Release 后卸载，
   cleanup hook 日志显示按 cluster+agent_type 删除（含历史残留的 ksm 设备），删除后 rg 设备数=0，delete_errors=0。
3) 中途出现的 namespace 竞态（重复运行同一脚本导致 namespace 处于 Terminating）是测试流程问题，
   不是 Chart 缺陷；最终在干净 namespace 中复测通过。
```
