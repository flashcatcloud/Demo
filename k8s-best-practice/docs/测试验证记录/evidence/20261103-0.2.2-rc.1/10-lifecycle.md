# CMD: G2 lifecycle: uninstall(with cleanup hook) -> install 0.2.1 -> upgrade 0.2.2-rc.1 -> rollback -> upgrade again
# AT: 2026-11-03T05:11:13Z / 2026-11-03T13:11:13+0800

## 0. 推送待测包到测试主机
```
$ scp categraf-0.2.2-rc.1.tgz root@100.98.231.109:/root/categraf-0.2.2-rc.1.tgz
(scp 成功)
$ sha256sum（远端）
88d9449a809096b60866355e58bdee5a7bb6488a9ff683252adad8b35a238a3a  /root/categraf-0.2.2-rc.1.tgz
```
### G2-0 卸载前基线（0.2.4 rev8）
```
$ helm list -n categraf
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART         	APP VERSION
categraf	categraf 	8       	2026-11-03 12:09:52.209454825 +0800 CST	deployed	categraf-0.2.4	1.0.0      
$ kubectl get pods -n categraf --no-headers | 统计
      6 Running
$ Flashcat 设备（cluster=k8s-flashcat-test-20261029）
  k8s-flashcat-test-20261029-categraf-ksm-0 target_up=2
  k8s-node1 target_up=2
  k8s-node2 target_up=2
  本集群设备数=3  全库=6
$ VM count({cluster=...}) 与 up 作业
  series=13754
   1   up=1 job=app-metrics
   2   up=1 job=coredns
   2   up=1 job=kube-proxy
   1   up=1 job=kube-state-metrics
   4   up=1 job=kubelet
```
## 1. helm uninstall（观察 pre-delete cleanup hook）
```
$ 后台监听 cleanup hook pod，卸载同时抓日志
$ helm uninstall categraf -n categraf
release "categraf" uninstalled

--- 等待 hook 日志落盘 ---
-rw-r--r-- 1 root root 1755 Nov  3 13:11 /root/cleanup-hook.log

--- cleanup hook 日志 ---
2026-11-03T05:11:31Z	INFO	setup	configuration loaded	{"flashcat_addr": "http://flashcat.local:19000", "cluster_name": "k8s-flashcat-test-20261029", "wait_duration": "4h0m0s", "reconcile_interval": "5m0s", "max_node_stale": "168h0m0s"}
2026-11-03T05:11:31Z	INFO	setup	cleanup-once mode: starting Flashcat uninstall cleanup	{"flashcat_addr": "http://flashcat.local:19000", "cluster_name": "k8s-flashcat-test-20261029"}
2026-11-03T05:11:31Z	INFO	cleanup-once started	{"cluster": "k8s-flashcat-test-20261029", "cleanup_node_categraf": true, "cleanup_ksm_categraf": true}
2026-11-03T05:11:31Z	INFO	operator Deployment deletion requested	{"name": "categraf-operator", "namespace": "categraf"}
2026-11-03T05:11:31Z	INFO	nodeAgent DaemonSet deletion requested	{"name": "categraf", "namespace": "categraf"}
2026-11-03T05:11:31Z	INFO	ksmAgent StatefulSet deletion requested	{"name": "categraf-ksm", "namespace": "categraf"}
2026-11-03T05:11:56Z	INFO	all heartbeats stopped	{"agent_type": "nodeAgent", "targets": 2}
2026-11-03T05:11:56Z	INFO	deleted target	{"ident": "k8s-node1"}
2026-11-03T05:11:56Z	INFO	deleted target	{"ident": "k8s-node2"}
2026-11-03T05:11:56Z	INFO	target cleanup completed	{"cluster": "k8s-flashcat-test-20261029", "agent_type": "nodeAgent", "total_targets": 2, "delete_errors": 0}
2026-11-03T05:11:56Z	INFO	all heartbeats stopped	{"agent_type": "ksmAgent", "targets": 1}
2026-11-03T05:11:56Z	INFO	deleted target	{"ident": "k8s-flashcat-test-20261029-categraf-ksm-0"}
2026-11-03T05:11:56Z	INFO	target cleanup completed	{"cluster": "k8s-flashcat-test-20261029", "agent_type": "ksmAgent", "total_targets": 1, "delete_errors": 0}
2026-11-03T05:11:56Z	INFO	cleanup-once completed
2026-11-03T05:11:56Z	INFO	setup	cleanup-once completed successfully

--- 卸载后集群对象 ---
NAME	NAMESPACE	REVISION	UPDATED	STATUS	CHART	APP VERSION

NAME                                          READY   STATUS    RESTARTS   AGE
pod/annotated-metrics-test-58c756859d-km2kn   1/1     Running   0          82m

NAME                                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/annotated-metrics-test   1/1     1            1           82m

NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      4d18h

(无残留 ds/sts)
```
### G2-1 卸载后（设备应被 cleanup hook 删除）
```
$ helm list -n categraf
NAME	NAMESPACE	REVISION	UPDATED	STATUS	CHART	APP VERSION
$ kubectl get pods -n categraf --no-headers | 统计
      1 Running
$ Flashcat 设备（cluster=k8s-flashcat-test-20261029）
  本集群设备数=0  全库=3
$ VM count({cluster=...}) 与 up 作业
  series=ERR
```
## 2. 安装生产版 0.2.1（从 OCI）
```
$ helm upgrade --install categraf oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1 -n categraf --create-namespace -f /root/categraf-024-regression-values.yaml
Release "categraf" does not exist. Installing it now.
Pulled: registry.flashcat.cloud/public/charts/categraf:0.2.1
Digest: sha256:f816e2331d1ccda9aed641b7b41abf892a69af012b264c5108fb41743292eefc
NAME: categraf
LAST DEPLOYED: Tue Nov  3 13:22:15 2026
NAMESPACE: categraf
STATUS: deployed
REVISION: 1
TEST SUITE: None

$ 等待工作负载就绪
deployment.apps/annotated-metrics-test condition met
deployment.apps/categraf-kube-state-metrics condition met
deployment.apps/categraf-operator condition met
daemon set "categraf" successfully rolled out
error: unknown flag: --all
See 'kubectl rollout status --help' for usage.

$ helm list / kubectl get pods
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART         	APP VERSION
categraf	categraf 	1       	2026-11-03 13:22:15.759506738 +0800 CST	deployed	categraf-0.2.1	1.0.0      

NAME                                           READY   STATUS    RESTARTS   AGE   IP             NODE        NOMINATED NODE   READINESS GATES
annotated-metrics-test-58c756859d-km2kn        1/1     Running   0          83m   10.244.1.22    k8s-node2   <none>           <none>
categraf-4mbzq                                 1/1     Running   0          11s   192.168.31.5   k8s-node1   <none>           <none>
categraf-dbw8m                                 1/1     Running   0          11s   192.168.31.6   k8s-node2   <none>           <none>
categraf-ksm-0                                 1/1     Running   0          11s   10.244.1.27    k8s-node2   <none>           <none>
categraf-kube-state-metrics-844f8d85fb-pn7w7   1/1     Running   0          11s   10.244.1.29    k8s-node2   <none>           <none>
categraf-operator-7c89787646-hd4mr             1/1     Running   0          11s   10.244.1.28    k8s-node2   <none>           <none>
```
### G2-2 安装 0.2.1 后
```
$ helm list -n categraf
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART         	APP VERSION
categraf	categraf 	1       	2026-11-03 13:22:15.759506738 +0800 CST	deployed	categraf-0.2.1	1.0.0      
$ kubectl get pods -n categraf --no-headers | 统计
      6 Running
$ Flashcat 设备（cluster=k8s-flashcat-test-20261029）
  本集群设备数=0  全库=6
$ VM count({cluster=...}) 与 up 作业
  series=115
```
### 2.1 0.2.1 的已知能力基线（作为对比证据）
```
$ 0.2.1 node config.toml [global.labels] 段
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029"
categraf = "nodeAgent"
[global.n9e_server]

$ 0.2.1 cluster-scrape.yaml 的 app-metrics job（是否缺 metrics_path 默认值）
  external_labels:
  - job_name: 'kube-state-metrics'
  - job_name: 'app-metrics'
        target_label: __metrics_path__
  - job_name: 'coredns'

$ VM: up{job="app-metrics"}（0.2.1 的 path relabel 修复情况）
```
## 3. 从 0.2.1 升级到 0.2.2-rc.1（真实升级路径）
```
升级前 revision=1
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml --timeout 300s
Release "categraf" has been upgraded. Happy Helming!
NAME: categraf
LAST DEPLOYED: Tue Nov  3 13:22:47 2026
NAMESPACE: categraf
STATUS: deployed
REVISION: 2
TEST SUITE: None

$ helm history（末 4 行）
REVISION	UPDATED                 	STATUS    	CHART              	APP VERSION	DESCRIPTION     
1       	Tue Nov  3 13:22:15 2026	superseded	categraf-0.2.1     	1.0.0      	Install complete
2       	Tue Nov  3 13:22:47 2026	deployed  	categraf-0.2.2-rc.1	0.5.32     	Upgrade complete

$ 等待工作负载就绪
deployment.apps/annotated-metrics-test condition met
deployment.apps/categraf-kube-state-metrics condition met
deployment.apps/categraf-operator condition met
daemon set "categraf" successfully rolled out
error: unknown flag: --all
See 'kubectl rollout status --help' for usage.

$ kubectl get pods -o wide
NAME                                           READY   STATUS    RESTARTS   AGE   IP             NODE        NOMINATED NODE   READINESS GATES
annotated-metrics-test-58c756859d-km2kn        1/1     Running   0          83m   10.244.1.22    k8s-node2   <none>           <none>
categraf-4mbzq                                 1/1     Running   0          34s   192.168.31.5   k8s-node1   <none>           <none>
categraf-dbw8m                                 1/1     Running   0          34s   192.168.31.6   k8s-node2   <none>           <none>
categraf-ksm-0                                 1/1     Running   0          34s   10.244.1.27    k8s-node2   <none>           <none>
categraf-kube-state-metrics-844f8d85fb-pn7w7   1/1     Running   0          34s   10.244.1.29    k8s-node2   <none>           <none>
categraf-operator-7c89787646-hd4mr             1/1     Running   0          34s   10.244.1.28    k8s-node2   <none>           <none>
$ helm get values 是否保持（脱敏）
appMetrics:
  enabled: true
  extraScrapeConfigs: []
categraf:
  clusterName: k8s-flashcat-test-20261029
  config:
    interval: 20
  customLabels:
    environment: test
    owner: platform
  env: test
  heartbeat:
    dialTimeout: 3000
    interval: 12
    timeout: 6000
  heartbeatGid: "2"
  serverAddr: http://flashcat.local:19000
  writer:
    batch: 3000
    chanSize: 1500000
operator:
  enabled: true
  userToken: <REDACTED>
```
### G2-3 升级到 rc.1 后
```
$ helm list -n categraf
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART              	APP VERSION
categraf	categraf 	2       	2026-11-03 13:22:47.952008724 +0800 CST	deployed	categraf-0.2.2-rc.1	0.5.32     
$ kubectl get pods -n categraf --no-headers | 统计
      6 Running
$ Flashcat 设备（cluster=k8s-flashcat-test-20261029）
  k8s-flashcat-test-20261029-categraf-ksm-0 target_up=2
  k8s-node1 target_up=2
  k8s-node2 target_up=2
  本集群设备数=3  全库=6
$ VM count({cluster=...}) 与 up 作业
  series=11874
   1   up=1 job=coredns
   2   up=1 job=kube-proxy
   1   up=1 job=kube-state-metrics
   4   up=1 job=kubelet
```
## 4. helm rollback 回 0.2.1，再升级回 rc.1
```
$ helm rollback categraf 1 -n categraf
Rollback was a success! Happy Helming!

$ 回滚后状态
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART         	APP VERSION
categraf	categraf 	3       	2026-11-03 13:23:04.898987879 +0800 CST	deployed	categraf-0.2.1	1.0.0      
6

$ 再升级回 rc.1
Release "categraf" has been upgraded. Happy Helming!
NAME: categraf
LAST DEPLOYED: Tue Nov  3 13:23:06 2026
NAMESPACE: categraf
STATUS: deployed
REVISION: 4
TEST SUITE: None
deployment.apps/annotated-metrics-test condition met
deployment.apps/categraf-kube-state-metrics condition met
deployment.apps/categraf-operator condition met
daemon set "categraf" successfully rolled out
error: unknown flag: --all
See 'kubectl rollout status --help' for usage.

$ 最终状态
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART              	APP VERSION
categraf	categraf 	4       	2026-11-03 13:23:06.305775954 +0800 CST	deployed	categraf-0.2.2-rc.1	0.5.32     
```
### G2-4 回滚并再次升级后（最终态 rc.1）
```
$ helm list -n categraf
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART              	APP VERSION
categraf	categraf 	4       	2026-11-03 13:23:06.305775954 +0800 CST	deployed	categraf-0.2.2-rc.1	0.5.32     
$ kubectl get pods -n categraf --no-headers | 统计
      6 Running
$ Flashcat 设备（cluster=k8s-flashcat-test-20261029）
  k8s-flashcat-test-20261029-categraf-ksm-0 target_up=2
  k8s-node1 target_up=2
  k8s-node2 target_up=2
  本集群设备数=3  全库=6
$ VM count({cluster=...}) 与 up 作业
  series=12411
   2   up=1 job=coredns
   2   up=1 job=kube-proxy
   1   up=1 job=kube-state-metrics
   4   up=1 job=kubelet
```
## 5. 汇总
```
revision 轨迹:
REVISION	UPDATED                 	STATUS    	CHART              	APP VERSION	DESCRIPTION     
1       	Tue Nov  3 13:22:15 2026	superseded	categraf-0.2.1     	1.0.0      	Install complete
2       	Tue Nov  3 13:22:47 2026	superseded	categraf-0.2.2-rc.1	0.5.32     	Upgrade complete
3       	Tue Nov  3 13:23:04 2026	superseded	categraf-0.2.1     	1.0.0      	Rollback to 1   
4       	Tue Nov  3 13:23:06 2026	deployed  	categraf-0.2.2-rc.1	0.5.32     	Upgrade complete

最终设备:
  k8s-flashcat-test-20261029-categraf-ksm-0 target_up=2 group_names=null
  k8s-node1 target_up=2 group_names=null
  k8s-node2 target_up=2 group_names=null
```
