# CMD: G4(lean) feature matrix：合并独立用例，每例 apply->assert->restore；基线 values=/root/categraf-024-regression-values.yaml
# AT: 2026-11-03T06:10:02Z / 2026-11-03T14:10:02+0800

## C1 (4.1) customLabels region=cn-shanghai
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml --set categraf.customLabels.region=cn-shanghai
STATUS: deployed
REVISION: 13
TEST SUITE: None
```
### C1 断言
```
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029"
categraf = "nodeAgent"
environment = "test"
owner = "platform"
region = "cn-shanghai"

[global.n9e_server]
global:
  scrape_interval: 15s
  external_labels:
    cluster: "k8s-flashcat-test-20261029"
    environment: "test"
    owner: "platform"
    region: "cn-shanghai"
    
scrape_configs:
  - job_name: 'kube-state-metrics'
metrics count({region="cn-shanghai"}) = 17417
  k8s-flashcat-test-20261029-categraf-ksm-0 region=cn-shanghai
  k8s-node1 region=cn-shanghai
  k8s-node2 region=cn-shanghai
```
## 恢复基线 values
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml 
STATUS: deployed
REVISION: 14
TEST SUITE: None
```
## C2 (4.2/4.12/4.14) 参数变更 + hostExec 关 + privileged=false + operator 关
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml --set categraf.config.interval=25 --set categraf.writer.batch=4000 --set categraf.heartbeat.interval=15 --set categraf.heartbeat.timeout=7000 --set categraf.heartbeat.dialTimeout=3500 --set nodeCategraf.hostExec.enabled=false --set nodeCategraf.securityContext.privileged=false --set operator.enabled=false
STATUS: deployed
REVISION: 15
TEST SUITE: None
```
### C2 断言
```
[global]
interval = 25
batch = 4000
chan_size = 1500000
[heartbeat]
interval = 15
timeout = 7000
dial_timeout = 3500
--- node agent securityContext / ibex / HOST_EXEC ---
{"allowPrivilegeEscalation":false,"capabilities":{"add":["SYSLOG"],"drop":["ALL"]},"privileged":false}
ibex volumes: 0
HOST_EXEC_PROFILE=false
--- operator 资源 ---
(operator 已移除)
设备数=3
```
## 恢复基线 values
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml 
STATUS: deployed
REVISION: 16
TEST SUITE: None
```
## C3 (4.4) extraScrapeConfigs 注入 customer-custom-job
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml -f /root/categraf-extra-scrape-values.yaml
STATUS: deployed
REVISION: 17
TEST SUITE: None
```
### C3 断言
```
9:  - job_name: 'kube-state-metrics'
16:  - job_name: 'app-metrics'
56:  - job_name: customer-custom-job
71:  - job_name: 'coredns'
78:  - job_name: 'calico'
89:  - job_name: 'cilium'
up{job="customer-custom-job"} = 1
```
### C3-负向：extraScrapeConfigs 非 list
```
$ helm upgrade --set appMetrics.extraScrapeConfigs=notalist（应失败且不改 revision）
Error: UPGRADE FAILED: execution error at (categraf/templates/ksm-categraf.yaml:68:10): appMetrics.extraScrapeConfigs must be a list
revision: 17 -> 17
```
## 恢复基线 values
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml 
STATUS: deployed
REVISION: 18
TEST SUITE: None
```
## C4 (4.3) annotation 自动发现：改坏 prometheus.io/path 验证 relabel 生效
```
改前 up{job="app-metrics"} = 1
  up=1 instance=10.244.1.22:8080 service=annotated-metrics-test team=platform namespace=categraf
  up=1 instance=10.244.1.22:8080 service=annotated-metrics-test team=platform namespace=categraf
Waiting for deployment "annotated-metrics-test" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "annotated-metrics-test" rollout to finish: 1 old replicas are pending termination...
deployment "annotated-metrics-test" successfully rolled out
--- 等待 75s ---
改坏后 up = 1
Waiting for deployment "annotated-metrics-test" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "annotated-metrics-test" rollout to finish: 1 old replicas are pending termination...
deployment "annotated-metrics-test" successfully rolled out
--- 等待 60s ---
恢复后 up = 1
```
## C5 (4.11) inputs 组合关闭：cadvisor / nodeExporter / hostNative.disk
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml --set nodeCategraf.inputs.cadvisor=false --set nodeCategraf.inputs.nodeExporter=false --set nodeCategraf.inputs.hostNative.disk=false
STATUS: deployed
REVISION: 19
TEST SUITE: None
```
### C5 断言
```
/opt/categraf/conf/input.prometheus/kube-proxy.toml
/opt/categraf/conf/input.cpu/cpu.toml
/opt/categraf/conf/input.mem/mem.toml
/opt/categraf/conf/input.disk
/opt/categraf/conf/input.diskio/diskio.toml
/opt/categraf/conf/input.net/net.toml
/opt/categraf/conf/input.netstat/netstat.toml
/opt/categraf/conf/input.system/system.toml
/opt/categraf/conf/input.kernel/kernel.toml
/opt/categraf/conf/input.swap/swap.toml
/opt/categraf/conf/input.processes/processes.toml
/opt/categraf/conf/input.syslog
count_over_time(up{job="kubelet"}[90s])       = 4
count_over_time(node_cpu_seconds_total[90s])   = 64
count_over_time(disk_used[90s])                = 121
```
## 恢复基线 values
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml 
STATUS: deployed
REVISION: 20
TEST SUITE: None
```
## C6 (4.5/4.6/4.7/4.9/4.10) 组件组合：KS 指标 job 关 + coreDns 关 + kubeProxy 关 + networkPlugin 关 + controlPlane 开
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml --set ksmCategraf.jobs.kubeStateMetrics=false --set coreDns.enabled=false --set kubeProxy.enabled=false --set networkPlugin.calico.enabled=false --set networkPlugin.cilium.enabled=false --set controlPlane.enabled=true
STATUS: deployed
REVISION: 21
TEST SUITE: None
```
### C6 断言
```
9:  - job_name: 'app-metrics'
49:  - job_name: 'apiserver'
63:  - job_name: 'kube-controller-manager'
81:  - job_name: 'kube-scheduler'
99:  - job_name: 'etcd'
--- 等待 100s ---
  up{coredns}=1  (90s series=0)
  up{kube-proxy}=1  (90s series=2)
  up{kube-state-metrics}=1  (90s series=0)
  up{apiserver}=absent  (90s series=0)
  up{kube-controller-manager}=0  (90s series=1)
  up{kube-scheduler}=0  (90s series=1)
  up{etcd}=0  (90s series=1)
  up{calico}=absent  (90s series=0)
  up{cilium}=absent  (90s series=0)
--- 控制平面 job 渲染 ---
  - job_name: 'apiserver'
  - job_name: 'kube-controller-manager'
  - job_name: 'kube-scheduler'
  - job_name: 'etcd'
```
## 恢复基线 values
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml 
STATUS: deployed
REVISION: 22
TEST SUITE: None
```
## C7 (4.5) kubeStateMetrics.enabled=false
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml --set kubeStateMetrics.enabled=false
STATUS: deployed
REVISION: 23
TEST SUITE: None
```
### C7 断言
```
(KSM Deployment/Service 已移除)
up{job="kube-state-metrics"} = 1
```
## 恢复基线 values
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml 
STATUS: deployed
REVISION: 24
TEST SUITE: None
```
## C9 (4.13) 多 Release 隔离（ns=categraf-rg, clusterName=…-rg, hostname 模板）
```
Release "categraf-rg" does not exist. Installing it now.
Error: open /root/categraf-rg-values.yaml: no such file or directory
--- 资源命名 ---

--- ClusterRole 隔离 ---
categraf-categraf-kube-state-metrics                                   2026-11-03T06:24:27Z
categraf-categraf-node-agent                                           2026-11-03T05:22:16Z
categraf-categraf-operator                                             2026-11-03T06:11:05Z
--- 等待 50s 设备 ---
--- 主集群设备 ---
  k8s-flashcat-test-20261029-categraf-ksm-0 target_up=2
  k8s-node1 target_up=2
  k8s-node2 target_up=2
```
### C9 卸载：cleanup hook 只删本集群设备
```
Error: uninstall: Release not loaded: categraf-rg: release: not found
rg 设备数=  主集群=3
```
## 恢复基线 values
```
$ helm upgrade categraf /root/categraf-0.2.2-rc.1.tgz -n categraf -f /root/categraf-024-regression-values.yaml 
STATUS: deployed
REVISION: 25
TEST SUITE: None
```
## 收尾：最终状态
```
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART              	APP VERSION
categraf	categraf 	25      	2026-11-03 14:27:32.792551531 +0800 CST	deployed	categraf-0.2.2-rc.1	0.5.32     

NAME                                           READY   STATUS    RESTARTS   AGE     IP             NODE        NOMINATED NODE   READINESS GATES
annotated-metrics-test-58c756859d-6d295        1/1     Running   0          13m     10.244.1.57    k8s-node2   <none>           <none>
categraf-ksm-0                                 1/1     Running   0          3m50s   10.244.1.70    k8s-node2   <none>           <none>
categraf-kube-state-metrics-844f8d85fb-j762m   1/1     Running   0          3m52s   10.244.1.68    k8s-node2   <none>           <none>
categraf-ljqqh                                 1/1     Running   0          3m50s   192.168.31.5   k8s-node1   <none>           <none>
categraf-operator-7c89787646-lrtd4             1/1     Running   0          3m52s   10.244.1.69    k8s-node2   <none>           <none>
categraf-rbqzd                                 1/1     Running   0          3m51s   192.168.31.6   k8s-node2   <none>           <none>
设备 target_up=2: 3/3
up 异常条数: 0
series: 15218
```
