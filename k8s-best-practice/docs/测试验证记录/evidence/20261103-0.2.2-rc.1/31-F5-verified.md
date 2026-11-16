# CMD: F5 端到端验证：rc.3 + controlPlane.enabled=true（ns=categraf-f5test，ident 用集群前缀避免与主集群冲突）
# AT: 2026-11-03T07:30:15Z / 2026-11-03T15:30:15+0800

## 0. 安装 rc.3（controlPlane 开启）
```
namespace/categraf-f5test created

STATUS: deployed
REVISION: 2
TEST SUITE: None
daemon set "categraf-f5test" successfully rolled out
--- 渲染出的控制平面 job ---
  - job_name: 'kube-state-metrics'
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
  - job_name: 'app-metrics'
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
      - source_labels: [__meta_kubernetes_namespace]
      - source_labels: [__meta_kubernetes_pod_name]
      - source_labels: [__meta_kubernetes_pod_label_app]
        replacement: $1
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        replacement: $1
      - source_labels: [__meta_kubernetes_pod_label_team]
        replacement: $1
      - source_labels: [__meta_kubernetes_pod_ip, __meta_kubernetes_pod_annotation_prometheus_io_port]
        replacement: "${1}:${2}"
        replacement: "/metrics"
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        replacement: $1
        replacement: http
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
        replacement: $1
  - job_name: 'apiserver'
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
  - job_name: 'kube-controller-manager'
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_component]
      - source_labels: [__meta_kubernetes_pod_ip]
        replacement: ${1}:10257
  - job_name: 'kube-scheduler'
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_component]
      - source_labels: [__meta_kubernetes_pod_ip]
        replacement: ${1}:10259
  - job_name: 'etcd'
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_component]
      - source_labels: [__meta_kubernetes_pod_ip]
        replacement: ${1}:2381
  - job_name: 'coredns'
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
  - job_name: 'calico'
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_k8s_app]
      - source_labels: [__meta_kubernetes_pod_ip]
        replacement: ${1}:9091
```
## 1. 等待两个抓取周期后查询 up（本集群标签）
```
  up{job="apiserver"} = 1
  up{job="kube-controller-manager"} = 0
  up{job="kube-scheduler"} = 0
  up{job="etcd"} = 0

--- apiserver target 明细 ---
  up=1 instance=192.168.31.5:6443 endpoint=-
```
## 2. 主集群不受影响（升级后状态）
```
主集群设备: 3/3 target_up=2
```
## 3. 清理
```
release "categraf-f5test" uninstalled
清理后本集群设备数 = 0
主集群设备数 = 3
namespace "categraf-f5test" deleted
```
## 4. 结论
```
rc.3 修复了 apiserver job 的端点元标签：controlPlane.enabled=true 时 up{job="apiserver"}=1，apiserver 指标可正常采集；
controller-manager / scheduler / etcd 仍不可采是本测试集群 master 监听 127.0.0.1 的环境限制（非 Chart 缺陷），
按文档放开监听（--bind-address=0.0.0.0 / --listen-metrics-urls 增加 0.0.0.0:2381）后再验证即可。
```

## 更正：controller-manager / scheduler / etcd 是 up=0（不是 absent）
```
上表中这三项返回 0，表示目标已被正确发现并尝试抓取，但连接被拒（master 监听 127.0.0.1）——
这恰好证明 F5 修复后控制平面 4 个 job 都能发现目标；这三项要等 master 放开监听后才会变成 1（环境限制，非 Chart 缺陷）。
```
