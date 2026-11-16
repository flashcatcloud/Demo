# CMD: G0 baseline: helm/kubectl/Flashcat/VM 全量只读快照
# AT: 2026-11-03T05:04:58Z / 2026-11-03T13:04:58+0800

## A. 时间与工具版本
```
local: 2026-11-03T13:04:58+0800 / host: 2026-11-03T13:04:59+0800
local helm: v4.2.3+g43e8b7f
local kubectl client: gitVersion:v1.36.1
remote helm: v3.21.3+g1ad6e68
remote kubectl: gitVersion:v1.28.2
package: 88d9449a809096b60866355e58bdee5a7bb6488a9ff683252adad8b35a238a3a  (17146 bytes)
```
## B. 当前 Release 状态（改装前）
```
$ helm list -n categraf -o json
[
    {
        "name": "categraf",
        "namespace": "categraf",
        "revision": "8",
        "updated": "2026-11-03 12:09:52.209454825 +0800 CST",
        "status": "deployed",
        "chart": "categraf-0.2.4",
        "app_version": "1.0.0"
    }
]

$ helm history categraf -n categraf
REVISION	UPDATED                 	STATUS    	CHART         	APP VERSION	DESCRIPTION     
1       	Thu Oct 29 18:50:08 2026	superseded	categraf-0.2.3	1.0.0      	Install complete
2       	Thu Oct 29 18:51:41 2026	superseded	categraf-0.2.3	1.0.0      	Upgrade complete
3       	Thu Oct 29 18:52:52 2026	superseded	categraf-0.2.3	1.0.0      	Upgrade complete
4       	Thu Oct 29 18:54:09 2026	superseded	categraf-0.2.3	1.0.0      	Upgrade complete
5       	Tue Nov  3 11:40:45 2026	superseded	categraf-0.2.3	1.0.0      	Upgrade complete
6       	Tue Nov  3 11:42:00 2026	superseded	categraf-0.2.3	1.0.0      	Upgrade complete
7       	Tue Nov  3 11:42:55 2026	superseded	categraf-0.2.3	1.0.0      	Upgrade complete
8       	Tue Nov  3 12:09:52 2026	deployed  	categraf-0.2.4	1.0.0      	Upgrade complete
```
## C. 当前 values（token 脱敏）
```yaml
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
## D. 集群与工作负载
```
$ kubectl get nodes -o wide
NAME        STATUS   ROLES           AGE     VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
k8s-node1   Ready    control-plane   4d18h   v1.28.2   192.168.31.5   <none>        Ubuntu 22.04.5 LTS   5.15.0-190-generic   containerd://2.2.1
k8s-node2   Ready    <none>          4d18h   v1.28.2   192.168.31.6   <none>        Ubuntu 22.04.5 LTS   5.15.0-198-generic   containerd://2.2.1

$ kubectl get all -n categraf -o wide
NAME                                               READY   STATUS    RESTARTS       AGE     IP             NODE        NOMINATED NODE   READINESS GATES
pod/annotated-metrics-test-58c756859d-km2kn        1/1     Running   0              65m     10.244.1.22    k8s-node2   <none>           <none>
pod/categraf-ksm-0                                 1/1     Running   0              48m     10.244.1.25    k8s-node2   <none>           <none>
pod/categraf-kube-state-metrics-844f8d85fb-97vj2   1/1     Running   1 (110m ago)   4d18h   10.244.1.12    k8s-node2   <none>           <none>
pod/categraf-operator-7c89787646-z4f96             1/1     Running   0              55m     10.244.1.23    k8s-node2   <none>           <none>
pod/categraf-rhbst                                 1/1     Running   0              55m     192.168.31.6   k8s-node2   <none>           <none>
pod/categraf-xjpc9                                 1/1     Running   0              48m     192.168.31.5   k8s-node1   <none>           <none>

NAME                                  TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE     SELECTOR
service/categraf-kube-state-metrics   ClusterIP   None         <none>        8080/TCP   4d18h   app.kubernetes.io/instance=categraf,app.kubernetes.io/name=kube-state-metrics

NAME                      DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE     CONTAINERS   IMAGES                                                           SELECTOR
daemonset.apps/categraf   2         2         2       2            2           <none>          4d18h   categraf     registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.32   app=n9e,app.kubernetes.io/instance=categraf,component=categraf

NAME                                          READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS           IMAGES                                                                         SELECTOR
deployment.apps/annotated-metrics-test        1/1     1            1           65m     metrics              registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1   app.kubernetes.io/name=annotated-metrics-test
deployment.apps/categraf-kube-state-metrics   1/1     1            1           4d18h   kube-state-metrics   registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1   app.kubernetes.io/instance=categraf,app.kubernetes.io/name=kube-state-metrics
deployment.apps/categraf-operator             1/1     1            1           84m     operator             registry.flashcat.cloud/public/categraf-operator:0.0.7                         app=categraf,app.kubernetes.io/instance=categraf,component=operator

NAME                                                     DESIRED   CURRENT   READY   AGE     CONTAINERS           IMAGES                                                                         SELECTOR
replicaset.apps/annotated-metrics-test-58c756859d        1         1         1       65m     metrics              registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1   app.kubernetes.io/name=annotated-metrics-test,pod-template-hash=58c756859d
replicaset.apps/categraf-kube-state-metrics-844f8d85fb   1         1         1       4d18h   kube-state-metrics   registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1   app.kubernetes.io/instance=categraf,app.kubernetes.io/name=kube-state-metrics,pod-template-hash=844f8d85fb
replicaset.apps/categraf-operator-6c66b5f656             0         0         0       83m     operator             registry.flashcat.cloud/public/categraf-operator:0.0.7                         app=categraf,app.kubernetes.io/instance=categraf,component=operator,pod-template-hash=6c66b5f656
replicaset.apps/categraf-operator-785d8d7b5b             0         0         0       84m     operator             registry.flashcat.cloud/public/categraf-operator:0.0.7                         app=categraf,app.kubernetes.io/instance=categraf,component=operator,pod-template-hash=785d8d7b5b
replicaset.apps/categraf-operator-7c89787646             1         1         1       55m     operator             registry.flashcat.cloud/public/categraf-operator:0.0.7                         app=categraf,app.kubernetes.io/instance=categraf,component=operator,pod-template-hash=7c89787646

NAME                            READY   AGE     CONTAINERS   IMAGES
statefulset.apps/categraf-ksm   1/1     4d18h   categraf     registry.flashcat.cloud/public/categraf_ent:v0.5.32

$ kubectl -n categraf get pvc,lease,endpoints
NAME                                                          HOLDER                                                                    AGE
lease.coordination.k8s.io/categraf-node-cleanup.flashcat.io   categraf-operator-7c89787646-z4f96_6f9e9a57-01bd-400b-b073-76d948227f3a   4d18h

NAME                                    ENDPOINTS          AGE
endpoints/categraf-kube-state-metrics   10.244.1.12:8080   4d18h
categraf          categraf-node-cleanup.flashcat.io      categraf-operator-7c89787646-z4f96_6f9e9a57-01bd-400b-b073-76d948227f3a     4d18h
```
## E. 当前 ConfigMap（0.2.4 渲染结果，作为对照）
```
$ kubectl -n categraf get cm categraf-node-config -o jsonpath={.data.config\.toml}
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

--- ksm config.toml ---
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

--- cluster-scrape.yaml (job_name 列表) ---
  scrape_interval: 15s
  - job_name: 'kube-state-metrics'
  - job_name: 'app-metrics'
  - job_name: 'coredns'
  - job_name: 'calico'
  - job_name: 'cilium'
--- ConfigMap 清单 ---
configmap/categraf-config
configmap/categraf-disable-host
configmap/categraf-disable-syslog
configmap/categraf-input-cadvisor
configmap/categraf-input-cpu
configmap/categraf-input-disk
configmap/categraf-input-diskio
configmap/categraf-input-kernel
configmap/categraf-input-kube-proxy
configmap/categraf-input-mem
configmap/categraf-input-net
configmap/categraf-input-netstat
configmap/categraf-input-node-exporter
configmap/categraf-input-process
configmap/categraf-input-swap
configmap/categraf-input-system
configmap/categraf-ksm-config
configmap/categraf-ksm-scrape
configmap/categraf-operator-config
configmap/kube-root-ca.crt
```
## F. Flashcat 设备基线
```
$ fcapi /api/n9e/targets?limit=1000&p=1 | jq (cluster=本集群)
6	k8s-flashcat-test-20261029-categraf-ksm-0	target_up=2	agent=ent-v0.5.32	group_names=null	beat_time=1793682296	update_at=1793679377
4	k8s-node1	target_up=2	agent=ent-v0.5.32	group_names=null	beat_time=1793682297	update_at=1793677252
5	k8s-node2	target_up=2	agent=ent-v0.5.32	group_names=null	beat_time=1793682301	update_at=1793677250

本集群设备数: 3
全库设备数: 6
```
## G. VictoriaMetrics 指标基线
```
count({cluster="k8s-flashcat-test-20261029"}) = 13755
count(up) 全库 = 10

up{cluster=本集群}:
  up=1  job=coredns  instance=10.244.1.10:9153  pod=-
  up=1  job=coredns  instance=10.244.1.11:9153  pod=-
  up=1  job=kube-state-metrics  instance=10.244.1.12:8080  pod=-
  up=1  job=kube-proxy  instance=http://127.0.0.1:10249/metrics  pod=-
  up=1  job=kube-proxy  instance=http://127.0.0.1:10249/metrics  pod=-
  up=1  job=kubelet  instance=https://127.0.0.1:10250/metrics  pod=-
  up=1  job=kubelet  instance=https://127.0.0.1:10250/metrics  pod=-
  up=1  job=kubelet  instance=https://127.0.0.1:10250/metrics/cadvisor  pod=-
  up=1  job=kubelet  instance=https://127.0.0.1:10250/metrics/cadvisor  pod=-
  up=1  job=app-metrics  instance=10.244.1.22:8080  pod=annotated-metrics-test-58c756859d-km2kn

关键指标族存在性（count）:
  node_cpu_seconds_total                 64
  container_cpu_usage_seconds_total      58
  kube_pod_info                          32
  kube_node_info                         4
  cpu_usage_active                       2
  kube_node_status_condition             60
  diskio_read_bytes_total                无
```
## H. 控制平面监听参数（决定 controlPlane 采集用例预期）
```
--- kube-apiserver ---
["kube-apiserver","--advertise-address=192.168.31.5","--allow-privileged=true","--authorization-mode=Node,RBAC","--client-ca-file=/etc/kubernetes/pki/ca.crt","--enable-admission-plugins=NodeRestriction","--enable-bootstrap-token-auth=true","--etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt","--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt","--etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key","--etcd-servers=https://127.0.0.1:2379","--kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt","--kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key","--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname","--proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.crt","--proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client.key","--requestheader-allowed-names=front-proxy-client","--requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt","--requestheader-extra-headers-prefix=X-Remote-Extra-","--requestheader-group-headers=X-Remote-Group","--requestheader-username-headers=X-Remote-User","--secure-port=6443","--service-account-issuer=https://kubernetes.default.svc.cluster.local","--service-account-key-file=/etc/kubernetes/pki/sa.pub","--service-account-signing-key-file=/etc/kubernetes/pki/sa.key","--service-cluster-ip-range=10.96.0.0/12","--tls-cert-file=/etc/kubernetes/pki/apiserver.crt","--tls-private-key-file=/etc/kubernetes/pki/apiserver.key"]

--- kube-controller-manager ---
["kube-controller-manager","--allocate-node-cidrs=true","--authentication-kubeconfig=/etc/kubernetes/controller-manager.conf","--authorization-kubeconfig=/etc/kubernetes/controller-manager.conf","--bind-address=127.0.0.1","--client-ca-file=/etc/kubernetes/pki/ca.crt","--cluster-cidr=10.244.0.0/16","--cluster-name=kubernetes","--cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt","--cluster-signing-key-file=/etc/kubernetes/pki/ca.key","--controllers=*,bootstrapsigner,tokencleaner","--kubeconfig=/etc/kubernetes/controller-manager.conf","--leader-elect=true","--requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt","--root-ca-file=/etc/kubernetes/pki/ca.crt","--service-account-private-key-file=/etc/kubernetes/pki/sa.key","--service-cluster-ip-range=10.96.0.0/12","--use-service-account-credentials=true"]

--- kube-scheduler ---
["kube-scheduler","--authentication-kubeconfig=/etc/kubernetes/scheduler.conf","--authorization-kubeconfig=/etc/kubernetes/scheduler.conf","--bind-address=127.0.0.1","--kubeconfig=/etc/kubernetes/scheduler.conf","--leader-elect=true"]

--- etcd ---
["etcd","--advertise-client-urls=https://192.168.31.5:2379","--cert-file=/etc/kubernetes/pki/etcd/server.crt","--client-cert-auth=true","--data-dir=/var/lib/etcd","--experimental-initial-corrupt-check=true","--experimental-watch-progress-notify-interval=5s","--initial-advertise-peer-urls=https://192.168.31.5:2380","--initial-cluster=k8s-node1=https://192.168.31.5:2380","--key-file=/etc/kubernetes/pki/etcd/server.key","--listen-client-urls=https://127.0.0.1:2379,https://192.168.31.5:2379","--listen-metrics-urls=http://127.0.0.1:2381","--listen-peer-urls=https://192.168.31.5:2380","--name=k8s-node1","--peer-cert-file=/etc/kubernetes/pki/etcd/peer.crt","--peer-client-cert-auth=true","--peer-key-file=/etc/kubernetes/pki/etcd/peer.key","--peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt","--snapshot-count=10000","--trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt"]

--- 集群插件 / 网络 ---
coredns
etcd
kube
kube-apiserver
kube-controller-manager
kube-scheduler
```
## I. 测试主机上的包与临时文件
```
-rw-r--r-- 1 root root  1197 Nov  3 11:59 /root/annotated-metrics-test.yaml
-rw-r--r-- 1 root root 15716 Oct 29 18:54 /root/categraf-0.2.3.tgz
-rw------- 1 root root   470 Nov  3 12:09 /root/categraf-024-regression-values.yaml
-rw-r--r-- 1 root root 16426 Nov  3 12:09 /root/categraf-0.2.4.tgz
-rw------- 1 root root   684 Nov  3 11:41 /root/categraf-extra-regression-values.yaml
-rw------- 1 root root   325 Nov  3 11:40 /root/categraf-regression-values.yaml
-rw------- 1 root root   252 Oct 29 18:51 /root/categraf-test-values.yaml
-rw-r--r-- 1 root root  4178 Oct 29 18:47 /root/flannel-hostnetwork.yaml

无 categraf-rg 目录
```
