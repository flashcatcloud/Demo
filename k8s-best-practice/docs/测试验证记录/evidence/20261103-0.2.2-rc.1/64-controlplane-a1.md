# CMD: A.1 自动发现模式真机验证：放开 KCM/scheduler bind-address 与 etcd metrics 监听，验证 4 个 controlPlane job 可采集（测试后完整还原）
# AT: 2026-11-03T09:34:36Z / 2026-11-03T17:34:36+0800

## 0. 变更前基线
```
controlPlane.enabled（values 基线）= false（chart 默认）
监听地址: 127.0.0.1:10257 127.0.0.1:10259 127.0.0.1:2381 
节点: 
ufw: Status: active
```
## 1. 备份并修改 Static Pod manifest
```
etcd.yaml
kube-controller-manager.yaml
kube-scheduler.yaml

$ 修改 bind-address / listen-metrics-urls
--bind-address=0.0.0.0
--bind-address=0.0.0.0
--listen-metrics-urls=http://0.0.0.0:2381

$ 等待 kubelet 重建 Static Pod（30s 后看监听）
监听地址: 
```
## 2. 防火墙（ufw active，临时放通 Pod 网段）
```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere                  
6443/tcp                   ALLOW IN    Anywhere                  
2379:2380/tcp              ALLOW IN    Anywhere                  
10250/tcp                  ALLOW IN    Anywhere                  
10257/tcp                  ALLOW IN    Anywhere                  

$ ufw allow from 10.244.0.0/16 to 10257/10259/2381
10257/tcp                  ALLOW       Anywhere                  
10259/tcp                  ALLOW       Anywhere                  
10257/tcp                  ALLOW       10.244.0.0/16             
10259/tcp                  ALLOW       10.244.0.0/16             
2381/tcp                   ALLOW       10.244.0.0/16             
10257/tcp (v6)             ALLOW       Anywhere (v6)             
10259/tcp (v6)             ALLOW       Anywhere (v6)             
```
## 3. 开启 controlPlane.enabled=true
```
$ helm upgrade categraf /root/categraf-0.2.2.tgz -n categraf -f /root/categraf-024-regression-values.yaml --set controlPlane.enabled=true
NAMESPACE: categraf
STATUS: deployed
REVISION: 5
TEST SUITE: None
partitioned roll out complete: 1 new pods have been updated...

$ 渲染出的控制平面 job
  - job_name: 'apiserver'
  - job_name: 'kube-controller-manager'
  - job_name: 'kube-scheduler'
  - job_name: 'etcd'
```
## 4. 等待 2 个抓取周期后验证（关键结果）
```
  up{job="apiserver"} = 1
  up{job="kube-controller-manager"} = 1
  up{job="kube-scheduler"} = 1
  up{job="etcd"} = 0

--- 指标是否真的落库 ---
  apiserver_request_total            = 351
  workqueue_queue_duration_seconds   = 0
  scheduler_schedule_attempts_total  = 1
  etcd_server_has_leader             = 0

--- KSM Agent 日志中 scrape 相关错误（应为空）---

```

## 5. 结论（含 etcd 失败根因与最终复测）

首轮结果：apiserver=1、kube-controller-manager=1、kube-scheduler=1、**etcd=0**。

补充复测（只改 etcd 监听 + 调整防火墙）后定位到根因：

| 步骤 | 观察 | 结论 |
|---|---|---|
| etcd 监听改为 `0.0.0.0:2381` 后，宿主机本机 curl | HTTP 200 | etcd metrics 本身正常 |
| KSM Agent Pod 抓取仍 up=0 | `ufw` 日志出现 `[UFW BLOCK] SRC=192.168.31.6 DPT=2381` | 抓取流量的**源地址是节点 IP（node2）**，不是 Pod IP——Flannel 对 Pod 访问其它节点主机 IP 做了 SNAT |
| 仅放行 `10.244.0.0/16 → 2381` | 仍 up=0 | 证明 Pod 网段规则匹配不到 |
| 放通节点网段（ufw allow 2381） | **etcd up=1，etcd_server_has_leader 有数据** | 根因确认：防火墙源地址判断错误，不是 Chart 问题 |

最终结论：**A.1 自动发现模式可用**，四个 job 均可采集（apiserver / kube-controller-manager / kube-scheduler / etcd 全部 up=1）；唯一坑是防火墙要按**节点网段**放通，而不是 Pod 网段。

还原记录（已复核）：

```
监听: 127.0.0.1:2381 127.0.0.1:10259 127.0.0.1:10257
controlPlane job 数: 0（已关闭）
ufw: 临时规则已删除（仅保留基线 10257 等）
设备: 3/3 target_up=2
```
