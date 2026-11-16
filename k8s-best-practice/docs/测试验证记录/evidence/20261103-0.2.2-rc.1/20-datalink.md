# CMD: G3 datalink: 设备+心跳、VM 指标落库、agent 日志、rc.1 渲染配置
# AT: 2026-11-03T07:34:17Z / 2026-11-03T15:34:17+0800

## 3.1 Flashcat 设备与心跳
```
$ fcapi /api/n9e/targets?limit=1000（原始响应的本集群部分存 20-devices.json）
id=9 ident=k8s-flashcat-test-20261029-categraf-ksm-0 target_up=2 group_id=0 group_names=null agent=ent-v0.5.32 beat_time=1793691257
id=7 ident=k8s-node1 target_up=2 group_id=0 group_names=null agent=ent-v0.5.32 beat_time=1793691256
id=8 ident=k8s-node2 target_up=2 group_id=0 group_names=null agent=ent-v0.5.32 beat_time=1793691257

当前 epoch=1793691257
k8s-flashcat-test-20261029-categraf-ksm-0: beat_age=0s  update_age=49s
k8s-node1: beat_age=1s  update_age=598s
k8s-node2: beat_age=0s  update_age=591s
```
## 3.2 VictoriaMetrics 指标落库（instant 查询 lookback=5m，presence 即新鲜）
```
查询时间: 2026-11-03T15:34:17+0800
count({cluster="k8s-flashcat-test-20261029"}) = 17637
count(up{cluster})          = 10

up 明细（应全为 1）:
  up=1  job=coredns  instance=10.244.1.10:9153  pod=-  service=-
  up=1  job=coredns  instance=10.244.1.11:9153  pod=-  service=-
  up=1  job=kube-state-metrics  instance=10.244.1.106:8080  pod=-  service=-
  up=1  job=kube-proxy  instance=http://127.0.0.1:10249/metrics  pod=-  service=-
  up=1  job=kube-proxy  instance=http://127.0.0.1:10249/metrics  pod=-  service=-
  up=1  job=kubelet  instance=https://127.0.0.1:10250/metrics  pod=-  service=-
  up=1  job=kubelet  instance=https://127.0.0.1:10250/metrics  pod=-  service=-
  up=1  job=kubelet  instance=https://127.0.0.1:10250/metrics/cadvisor  pod=-  service=-
  up=1  job=kubelet  instance=https://127.0.0.1:10250/metrics/cadvisor  pod=-  service=-
  up=1  job=app-metrics  instance=10.244.1.95:8080  pod=annotated-metrics-test-58c756859d-pw94z  service=annotated-metrics-test

关键指标族:
  node_cpu_seconds_total                         224
  node_memory_MemAvailable_bytes                 7
  container_cpu_usage_seconds_total              264
  container_memory_working_set_bytes             271
  kube_pod_info                                  78
  kube_node_info                                 8
  kube_node_status_condition                     120
  cpu_usage_active                               6
  mem_used_percent                               7
  disk_used_percent                              645
  net_bits_recv                                  63
  process_open_fds                               19
  kube_proxy_sync_proxy_rules_duration_seconds   无
  coredns_dns_requests_total                     12

各节点上报（node_cpu_seconds_total by instance/host）:
  instance=k8s-flashcat-test-20261029-f5test-k8s-node1 series=96
  instance=k8s-flashcat-test-20261029-f5test-k8s-node2 series=64
  instance=k8s-node1 series=32
  instance=k8s-node2 series=32
```
## 3.3 rc.1 运行态 config.toml 与 scrape 配置
```
--- Node Agent config.toml ---
[global]
print_configs = false
hostname = "${HOSTNAME}"
omit_hostname = false
precision = "ms"
interval = 20
providers = ["local", "http", "rmq"]
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029"
categraf = "nodeAgent"
environment = "test"
owner = "platform"

[global.n9e_server]
address="http://flashcat.local:19000"
[writer_opt]
batch = 3000
chan_size = 1500000
[heartbeat]
enable = true
url = "http://flashcat.local:19000/v1/n9e-plus/heartbeat?gid=2"
interval = 12
timeout = 6000
dial_timeout = 3000

--- KSM Agent config.toml ---
[global]
interval = 20
providers = ["local"]
hostname = "${CLUSTER_NAME}-${HOSTNAME}"
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029"
categraf = "ksmAgent"
environment = "test"
owner = "platform"

[global.n9e_server]
address="http://flashcat.local:19000"
[writer_opt]
batch = 3000
chan_size = 1500000
[heartbeat]
enable = true
url = "http://flashcat.local:19000/v1/n9e-plus/heartbeat?gid=2"
interval = 12
timeout = 6000
dial_timeout = 3000
[prometheus]
enable = true
scrape_config_file = "/etc/categraf/cluster-scrape.yaml"
log_level = "info"

--- cluster-scrape.yaml: external_labels + job 列表 ---
2:  scrape_interval: 15s
3:  external_labels:
4:    cluster: "k8s-flashcat-test-20261029"
5:    environment: "test"
6:    owner: "platform"
9:  - job_name: 'kube-state-metrics'
16:  - job_name: 'app-metrics'
17:    metrics_path: /metrics
44:      - target_label: __metrics_path__
47:        target_label: __metrics_path__
56:  - job_name: 'coredns'
63:  - job_name: 'calico'
74:  - job_name: 'cilium'

--- Node Agent 关键 pod 规格 ---
[{"name":"TZ","value":"Asia/Shanghai"},{"name":"HOSTNAME","valueFrom":{"fieldRef":{"apiVersion":"v1","fieldPath":"spec.nodeName"}}},{"name":"HOSTIP","valueFrom":{"fieldRef":{"apiVersion":"v1","fieldPath":"status.hostIP"}}},{"name":"CLUSTER_NAME","value":"k8s-flashcat-test-20261029"},{"name":"HOST_PROC","value":"/hostfs/proc"},{"name":"HOST_SYS","value":"/hostfs/sys"},{"name":"HOST_MOUNT_PREFIX","value":"/hostfs"},{"name":"CATEGRAF_HOST_EXEC_PROFILE","value":"true"}]

--- 节点 Agent 实际运行节点 ---
NAME             READY   STATUS    RESTARTS   AGE   IP             NODE        NOMINATED NODE   READINESS GATES
categraf-drmkf   1/1     Running   0          58s   192.168.31.6   k8s-node2   <none>           <none>
categraf-jqpk9   1/1     Running   0          60s   192.168.31.5   k8s-node1   <none>           <none>
```
## 3.5 Operator 状态（leader lease / 探针 / 配置）
```
$ kubectl get lease（含 categraf 相关）
categraf          categraf-node-cleanup.flashcat.io      categraf-operator-85d84d7d5b-cfrc5_4a3cfea7-2625-4cf9-a71a-9a43f647ad0a     4d20h

$ operator configmap 环境变量
{
    "CATEGRAF_DAEMONSET_NAME": "categraf",
    "CATEGRAF_KSM_STATEFULSET_NAME": "categraf-ksm",
    "CATEGRAF_OPERATOR_DEPLOYMENT_NAME": "categraf-operator",
    "CLEANUP_KSM_CATEGRAF": "true",
    "CLEANUP_NODE_CATEGRAF": "true",
    "CLUSTER_NAME": "k8s-flashcat-test-20261029",
    "DEFAULT_WAIT_DURATION": "4h",
    "FLASHCAT_ADDR": "http://flashcat.local:19000",
    "HEARTBEAT_INTERVAL": "10s",
    "HEARTBEAT_STOP_FACTOR": "3",
    "MAX_NODE_STALE_DURATION": "168h",
    "NAMESPACE": "categraf",
    "RECONCILE_INTERVAL": "5m"
}

$ operator 最近日志中的 leader 相关
2026-11-03T07:33:24Z	INFO	setup	daemonset informer registered	{"watch_name": "categraf", "cleanup_node_categraf": true, "cleanup_ksm_categraf": true}
I1103 07:33:24.481353       1 leaderelection.go:250] attempting to acquire leader lease categraf/categraf-node-cleanup.flashcat.io...
I1103 07:33:51.964747       1 leaderelection.go:260] successfully acquired lease categraf/categraf-node-cleanup.flashcat.io
2026-11-03T07:33:51Z	DEBUG	events	categraf-operator-85d84d7d5b-cfrc5_4a3cfea7-2625-4cf9-a71a-9a43f647ad0a became leader	{"type": "Normal", "object": {"kind":"Lease","namespace":"categraf","name":"categraf-node-cleanup.flashcat.io","uid":"6a69c0f5-4616-465b-bcec-dd90029d87ad","apiVersion":"coordination.k8s.io/v1","resourceVersion":"39366"}, "reason": "LeaderElection"}
2026-11-03T07:33:51Z	INFO	cleanup loop started	{"interval": "5m0s", "stale_node_threshold": "168h0m0s"}
```
