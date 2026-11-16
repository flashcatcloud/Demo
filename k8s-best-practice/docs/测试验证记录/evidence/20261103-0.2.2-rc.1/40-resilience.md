# CMD: G5 resilience：逐类删除 Pod，记录重建耗时与恢复证据
# AT: 2026-11-03T07:00:13Z / 2026-11-03T15:00:13+0800

## 5.1 删除 Node Agent Pod
```
重建前 Pod: categraf-2224d
$ kubectl -n categraf delete pod categraf-2224d --wait=false
pod "categraf-2224d" deleted
```
```
重建后 Pod: categraf-vq64h（耗时 2s）
$ kubectl -n categraf get pods -l component=categraf -o wide
NAME             READY   STATUS    RESTARTS   AGE     IP             NODE        NOMINATED NODE   READINESS GATES
categraf-vq64h   1/1     Running   0          2m57s   192.168.31.6   k8s-node2   <none>           <none>
categraf-vslvt   1/1     Running   0          3s      192.168.31.5   k8s-node1   <none>           <none>
```
```
$ 30s 后设备状态: k8s-flashcat-test-20261029-categraf-ksm-0=2 k8s-node1=2 k8s-node2=2 
$ 30s 后 node 指标 2m 内 series: 128
```
## 5.2 删除 KSM Agent Pod
```
重建前 Pod: categraf-ksm-0
$ kubectl -n categraf delete pod categraf-ksm-0 --wait=false
pod "categraf-ksm-0" deleted
```
```
重建后 Pod: categraf-ksm-0（耗时 3s）
$ kubectl -n categraf get pods -l component=categraf-ksm -o wide
NAME             READY   STATUS    RESTARTS   AGE   IP             NODE        NOMINATED NODE   READINESS GATES
categraf-ksm-0   1/1     Running   0          2s    10.244.1.104   k8s-node2   <none>           <none>
```
```
$ 设备: k8s-flashcat-test-20261029-categraf-ksm-0=2 k8s-node1=2 k8s-node2=2 
$ up{job="kube-state-metrics"} = 1
```
## 5.3 删除 Operator Pod（重新选主）
```
重建前 Pod: categraf-operator-7c89787646-zm7z9
$ kubectl -n categraf delete pod categraf-operator-7c89787646-zm7z9 --wait=false
pod "categraf-operator-7c89787646-zm7z9" deleted
```
```
重建后 Pod: categraf-operator-7c89787646-s54q5（耗时 12s）
$ kubectl -n categraf get pods -l component=operator -o wide
NAME                                 READY   STATUS    RESTARTS   AGE   IP             NODE        NOMINATED NODE   READINESS GATES
categraf-operator-7c89787646-s54q5   1/1     Running   0          12s   10.244.1.105   k8s-node2   <none>           <none>
```
```
--- Lease 状态 ---
categraf-node-cleanup.flashcat.io   categraf-operator-7c89787646-s54q5_36a78b27-afbe-4c94-ac3b-55a2c63f1948   4d20h
--- operator 启动日志（leader 相关） ---
2026-11-03T07:01:12Z	INFO	setup	starting manager
2026-11-03T07:01:12Z	INFO	controller-runtime.metrics	Starting metrics server
2026-11-03T07:01:12Z	INFO	starting server	{"name": "health probe", "addr": "[::]:8081"}
I1103 07:01:12.860971       1 leaderelection.go:250] attempting to acquire leader lease categraf/categraf-node-cleanup.flashcat.io...
I1103 07:01:28.952276       1 leaderelection.go:260] successfully acquired lease categraf/categraf-node-cleanup.flashcat.io
2026-11-03T07:01:28Z	DEBUG	events	categraf-operator-7c89787646-s54q5_36a78b27-afbe-4c94-ac3b-55a2c63f1948 became leader	{"type": "Normal", "object": {"kind":"Lease","namespace":"categraf","name":"categraf-node-cleanup.flashcat.io","uid":"6a69c0f5-4616-465b-bcec-dd90029d87ad","apiVersion":"coordination.k8s.io/v1","resourceVersion":"33319"}, "reason": "LeaderElection"}
```
## 5.4 删除 kube-state-metrics Pod
```
重建前 Pod: categraf-kube-state-metrics-844f8d85fb-z6khd
$ kubectl -n categraf delete pod categraf-kube-state-metrics-844f8d85fb-z6khd --wait=false
pod "categraf-kube-state-metrics-844f8d85fb-z6khd" deleted
```
```
重建后 Pod: categraf-kube-state-metrics-844f8d85fb-m4sgf（耗时 3s）
$ kubectl -n categraf get pods -l app.kubernetes.io/name=kube-state-metrics -o wide
NAME                                           READY   STATUS    RESTARTS   AGE   IP             NODE        NOMINATED NODE   READINESS GATES
categraf-kube-state-metrics-844f8d85fb-m4sgf   1/1     Running   0          2s    10.244.1.106   k8s-node2   <none>           <none>
```
```
$ up{job="kube-state-metrics"} = 1
$ kube_pod_info 2m 内 series = 32
```
## 汇总：重建耗时
```
  5.1 删除 Node Agent Pod: 2s
  5.2 删除 KSM Agent Pod: 3s
  5.3 删除 Operator Pod（重新选主）: 12s
  5.4 删除 kube-state-metrics Pod: 3s
总耗时: 248s
```
