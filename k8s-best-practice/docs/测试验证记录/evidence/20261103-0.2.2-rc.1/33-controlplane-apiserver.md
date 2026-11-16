# CMD: 补充排查：controlPlane.enabled=true 时 apiserver job 永远发现不到目标（元标签用错）
# AT: 2026-11-03T06:42:42Z / 2026-11-03T14:42:42+0800

## A. 模板里两个 job 的端点元标签对比（静态证据）
```
$ grep -n "元标签" ../../../../assets/categraf-helm/categraf/templates/ksm-categraf.yaml
62:          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
125:          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_port_name]
182:          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
```
## B. 运行态配置（controlPlane 开启时）
```
  - job_name: 'apiserver'
    kubernetes_sd_configs:
      - role: endpoints
    scheme: https
    tls_config:
      insecure_skip_verify: true
    authorization:
      type: Bearer
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_port_name]
        action: keep
        regex: default;kubernetes;https

  - job_name: 'kube-controller-manager'
```
## C. 运行态指标：apiserver 是否曾经产生过 up 序列
```
count(count_over_time(up{job="apiserver"}[10m])) = 0
count(count_over_time(up{job="kube-state-metrics"}[10m])) = 1  (对照组，此时 job 已被关闭)
```
## D. 判断
```
apiserver job 的 keep 过滤器用了 __meta_kubernetes_port_name；endpoints 角色实际提供的是
__meta_kubernetes_endpoint_port_name（同文件 kube-state-metrics job 用的就是后者，且实测 up=1）。
因前者不存在，keep 过滤匹配不到任何端点 -> 该 job 无 target，up 序列从未产生。
→ controlPlane.enabled=true 时 apiserver 指标不可用（Chart 缺陷，F5）。
```
