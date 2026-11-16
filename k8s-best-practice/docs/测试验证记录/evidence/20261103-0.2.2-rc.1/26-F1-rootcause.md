# CMD: F1 根因精确复现——用真实回归 values 分别渲染 0.2.1 与 0.2.2-rc.1，对比 checksum 注解、渲染出的配置、以及 Pod 模板
# AT: 2026-11-03T07:17:06Z / 2026-11-03T15:17:06+0800

## 1. 关键点：两份 Chart 的 Pod 模板 checksum 注解完全相同
```
categraf-0.2.1.tgz       checksum/config: 2911955df9e08447e5583d463521688bf6bc74d6040b8c798ab041f9c38921e1
categraf-0.2.2-rc.1.tgz  checksum/config: 2911955df9e08447e5583d463521688bf6bc74d6040b8c798ab041f9c38921e1

而只改一个 values 值（env=prod）时：
rc.1 + env=prod          checksum/config: 5cad78c95c22110fe0ca5b9703f4718d462b78476e4bd0a6824fc25d2cbd0479
```

## 2. checksum 的计算方式：只哈希 .Values（不含渲染结果）
```
{{- define "categraf.valuesChecksum" -}}
{{- .Values | toYaml -}}
{{- end }}
```

## 3. 但渲染出来的配置确实变了（这就是“悄悄不生效”的部分）
```
--- Node Agent config.toml [global.labels] 段：0.2.1 vs rc.1 ---
[categraf-0.2.1.tgz]
    [global.labels]
    env = "test"
    cluster = "k8s-flashcat-test-20261029"
    categraf = "nodeAgent"
    [global.n9e_server]
    address="http://flashcat.local:19000"
    [writer_opt]
    batch = 2000
[categraf-0.2.2-rc.1.tgz]
    [global.labels]
    env = "test"
    cluster = "k8s-flashcat-test-20261029"
    categraf = "nodeAgent"
    environment = "test"
    owner = "platform"
    
    [global.n9e_server]

--- KSM scrape 的 app-metrics job（rc.1 修了 metrics_path / path relabel）---
[categraf-0.2.1.tgz]
      - job_name: 'app-metrics'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_metrics_scrape]
            action: keep
[categraf-0.2.2-rc.1.tgz]
      - job_name: 'app-metrics'
        metrics_path: /metrics
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
```

## 4. Pod 模板里唯一的“滚动触发器”就是这个 checksum 注解
```
DaemonSet 的 pod template 标签只有 app/component/instance，没有 helm.sh/chart / version 这类会随版本变化的标签：
        app: n9e
        component: categraf
        app.kubernetes.io/instance: t
--- 触发滚动的 annotate 在这里 ---
  template:
    metadata:
      labels:
--
  template:
    metadata:
```

## 5. 结论
```
用真实回归 values 渲染时，0.2.1 与 rc.1 的 checksum 完全相同（2911955d…），
因此 helm upgrade 不会改动 Pod 模板 → 不会滚动 → subPath 挂载的配置不会刷新；
但两份 Chart 渲染出的 config.toml / cluster-scrape.yaml 内容不同（见第 3 节）。
这就是“升级成功、Pod 全 Ready，但新功能没生效”的根因。
```
