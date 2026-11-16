# CMD: rc.3 主 Release 卸载 + 清理 Hook + 重装演练（ns=categraf）
# AT: 2026-11-03T07:59:00Z / 2026-11-03T15:59:00+0800

## 0. 卸载前基线（rc.3 rev37）
```
categraf	categraf 	43      	2026-11-03 15:57:57.172590929 +0800 CST	deployed	categraf-0.2.2-rc.3	0.5.32     
      6 Running
设备: 3 台，target_up=2: 3 台；其它集群设备: 3 台
指标 series: 19317；up 异常条数: 0
```
## 1. helm uninstall（观察 cleanup Hook）
```

$ helm uninstall categraf -n categraf
release "categraf" uninstalled

--- cleanup Hook 日志（设备删除）---
2026-11-03T07:59:34Z	INFO	all heartbeats stopped	{"agent_type": "nodeAgent", "targets": 2}
2026-11-03T07:59:34Z	INFO	deleted target	{"ident": "k8s-node1"}
2026-11-03T07:59:34Z	INFO	deleted target	{"ident": "k8s-node2"}
2026-11-03T07:59:34Z	INFO	target cleanup completed	{"cluster": "k8s-flashcat-test-20261029", "agent_type": "nodeAgent", "total_targets": 2, "delete_errors": 0}
2026-11-03T07:59:34Z	INFO	all heartbeats stopped	{"agent_type": "ksmAgent", "targets": 1}
2026-11-03T07:59:34Z	INFO	deleted target	{"ident": "k8s-flashcat-test-20261029-categraf-ksm-0"}
2026-11-03T07:59:34Z	INFO	target cleanup completed	{"cluster": "k8s-flashcat-test-20261029", "agent_type": "ksmAgent", "total_targets": 1, "delete_errors": 0}
2026-11-03T07:59:34Z	INFO	cleanup-once completed
2026-11-03T07:59:34Z	INFO	setup	cleanup-once completed successfully
```
## 2. 卸载后状态
```
release 数量: 0
NAME                                               READY   STATUS        RESTARTS   AGE
pod/annotated-metrics-test-58c756859d-pw94z        1/1     Running       0          65m
pod/categraf-kube-state-metrics-844f8d85fb-z2xqc   0/1     Terminating   0          100s

NAME                                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/annotated-metrics-test   1/1     1            1           4h
设备: 0 台；其它集群设备: 3 台
```
## 3. 用 rc.3 重新安装（同一份 values）
```
NAMESPACE: categraf
STATUS: deployed
REVISION: 1
TEST SUITE: None
daemon set "categraf" successfully rolled out
--- 等待 90s 让设备注册与指标上报 ---
categraf	categraf 	1       	2026-11-03 15:59:37.870803238 +0800 CST	deployed	categraf-0.2.2-rc.3	0.5.32     
      6 Running
设备: 3 台，target_up=2: 3 台
指标 series: 18240；up 异常条数: 0
customLabels: count({owner="platform"}) = 18240
app-metrics up = 1
```
## 4. 结论
```
rc.3 主 Release 的“卸载→设备清理→重装→设备重注册→数据恢复”整链路验证结果见上表。
```
