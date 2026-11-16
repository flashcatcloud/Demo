# CMD: G4 修正轮2：C4 用子查询消除 stale series；C6 apiserver 直连诊断；C9 多 Release 重测（含 push 校验）
# AT: 2026-11-03T06:52:40Z / 2026-11-03T14:52:40+0800

## C4-2 用子查询 (up==1)[60s:15s] 排除 stale series
```
基线: 60s 内 up=1 的 app-metrics series 数 = 1

改坏后: up 全集=[0]  60s 内 up=1 数=0
当前 Pod 注解:
{"prometheus.io/path":"/metrics-broken","prometheus.io/port":"8080","prometheus.io/scheme":"http","prometheus.io/scrape":"true"}

恢复后: 60s 内 up=1 数=1
```
### C4-2 结论记录
```
说明：上方三条为现场打印；最终断言使用改坏后/恢复后的独立查询（见 results.tsv C4-2 前缀）
```
## C6-2 controlPlane apiserver
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
up{job=apiserver} = []
--- KSM Agent 日志中 apiserver/scrape 错误 ---
time=2026-11-03T06:55:48.077Z level=INFO source=prometheus.go:335 msg="Loading configuration file" filename=/etc/categraf/cluster-scrape.yaml
time=2026-11-03T06:55:48.079Z level=INFO source=metadata_watcher.go:90 msg="Starting scraped metadata watcher" component=remote remote_name=7357fe url=http://flashcat.local:19000/prometheus/v1/write
time=2026-11-03T06:55:48.079Z level=INFO source=kubernetes.go:323 msg="Using pod service account via in-cluster config" component="discovery manager scrape" discovery=kubernetes config=coredns
time=2026-11-03T06:55:48.080Z level=INFO source=kubernetes.go:323 msg="Using pod service account via in-cluster config" component="discovery manager scrape" discovery=kubernetes config=cilium
time=2026-11-03T06:55:48.080Z level=INFO source=prometheus.go:362 msg="Completed loading of configuration file" filename=/etc/categraf/cluster-scrape.yaml totalDuration=2.426454ms
--- 从 KSM Pod 直连 apiserver /metrics 诊断 ---
/usr/bin/curl
curl_http=000
```
## C9-2 多 Release 重测
```
$ ls -l 远端 values 文件

$ helm upgrade --install categraf-rg
Release "categraf-rg" does not exist. Installing it now.
Error: open /root/categraf-rg-values.yaml: no such file or directory
$ 资源命名

$ ClusterRole

$ 等待 120s 设备
$ rg 内 Agent 日志（若没注册，查日志）

```
### C9-2 卸载
```
Error: uninstall: Release not loaded: categraf-rg: release: not found
rg 设备=3 主集群=3
```
