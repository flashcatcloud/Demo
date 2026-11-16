# CMD: F5 修复——apiserver job 端点元标签由 __meta_kubernetes_port_name 改为 __meta_kubernetes_endpoint_port_name
# AT: 2026-11-03T07:29:51Z / 2026-11-03T15:29:51+0800

## 1. 修复点（templates/_config.tpl，controlPlane 的 apiserver job）
```
151-  {{- end }}
152-  {{- if .Values.controlPlane.enabled }}
153:  - job_name: 'apiserver'
154-    kubernetes_sd_configs:
155-      - role: endpoints
```
## 2. 与同文件其它 endpoints job 一致性
```
100:      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
163:      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
220:      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
说明：kube-state-metrics（第 100 行）与 coredns（第 220 行）本来就用 endpoint_port_name，apiserver（第 163 行，原 port_name）现与之对齐。
```
## 3. 渲染差异（rc.3 vs rc.2，controlPlane.enabled=true）
```
  170c170
  <           - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_port_name]
  ---
  >           - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
  → 只改这一行，其它资源零变化

关闭 controlPlane 时 rc.3 与 rc.2 渲染差异行数:
         0
```
## 4. lint 与包
```
1 chart(s) linted, 0 chart(s) failed
rc.3 SHA256: 05f4d978f3e0c3f03aedc7831ee6fb7f10b54d12365a994c3fbb27ea05ca5f3f
appVersion: 0.5.32
kubeVersion: '>=1.19.0-0 <1.38.0-0'
version: 0.2.2-rc.3
```
