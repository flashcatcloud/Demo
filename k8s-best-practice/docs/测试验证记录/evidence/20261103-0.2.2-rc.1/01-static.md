# CMD: G1 static: helm show/lint/render，包=/Users/flashcat/Library/Mobile Documents/com~apple~CloudDocs/luomaojian/Demo/k8s-best-practice/categraf-0.2.2-rc.1.tgz
# AT: 2026-11-03T05:09:05Z / 2026-11-03T13:09:05+0800

## 1.1 包元数据
```
$ helm show chart categraf-0.2.2-rc.1.tgz
apiVersion: v2
appVersion: 0.5.32
description: K8S 指标监控采集 —— 基于 Categraf (DaemonSet + StatefulSet) 与 kube-state-metrics
home: https://flashcat.cloud/
keywords:
- categraf
- nightingale
- flashcat
- kube-state-metrics
- monitoring
kubeVersion: '>=1.19.0-0 <1.38.0-0'
maintainers:
- name: Flashcat
  url: https://flashcat.cloud/
name: categraf
type: application
version: 0.2.2-rc.1


$ shasum -a 256 / ls -l
88d9449a809096b60866355e58bdee5a7bb6488a9ff683252adad8b35a238a3a  /Users/flashcat/Library/Mobile Documents/com~apple~CloudDocs/luomaojian/Demo/k8s-best-practice/categraf-0.2.2-rc.1.tgz
-rw-r--r--@ 1 flashcat  staff  17146 Nov  3 12:55 /Users/flashcat/Library/Mobile Documents/com~apple~CloudDocs/luomaojian/Demo/k8s-best-practice/categraf-0.2.2-rc.1.tgz

$ tar tzf (文件清单)
categraf/Chart.yaml
categraf/values.yaml
categraf/templates/_helpers.tpl
categraf/templates/ksm-categraf.yaml
categraf/templates/kube-state-metrics.yaml
categraf/templates/node-categraf.yaml
categraf/templates/operator-cleanup-hook.yaml
categraf/templates/operator.yaml
categraf/templates/rbac.yaml
categraf/.helmignore
categraf/README.md
categraf/values-examples/values.all.yaml
categraf/values-examples/values.yaml
```
## 1.2 helm lint（3 组 values）
```
--- helm lint  ---
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
--- helm lint -f /Users/flashcat/Library/Mobile Documents/com~apple~CloudDocs/luomaojian/Demo/k8s-best-practice/assets/categraf-helm/categraf/values-examples/values.yaml ---
Error: open /Users/flashcat/Library/Mobile: no such file or directory
--- helm lint -f /Users/flashcat/Library/Mobile Documents/com~apple~CloudDocs/luomaojian/Demo/k8s-best-practice/assets/categraf-helm/categraf/values-examples/values.all.yaml ---
Error: open /Users/flashcat/Library/Mobile: no such file or directory
```
## 1.3 内容等价性：0.2.4 包 vs 0.2.2-rc.1 包（同一组 values，归一化版本标签后 diff）
```
$ diff -u <(render 0.2.4) <(render 0.2.2-rc.1)   # 归一化 helm.sh/chart 与 app.kubernetes.io/version
(无差异)

渲染行数: old=    1241 new=    1241
```
## 1.4 kubeVersion 矩阵
```
1.18.0  REJECT  Error: chart requires kubeVersion: >=1.19.0-0 <1.38.0-0 which is incompatible with Kubernetes v1.18.0
1.19.0  OK
1.20.0  OK
1.21.0  OK
1.28.2  OK
1.30.0  OK
1.31.0  OK
1.32.0  OK
1.34.0  OK
1.36.0  OK
1.37.0  OK
1.37.2  OK
1.38.0  REJECT  Error: chart requires kubeVersion: >=1.19.0-0 <1.38.0-0 which is incompatible with Kubernetes v1.38.0
```
## 1.8 边界观察：serverAddr 带尾斜杠
```
    address="http://192.168.31.14:19000/"
    url = "http://192.168.31.14:19000//v1/n9e-plus/heartbeat"
      - url: 'http://192.168.31.14:19000//prometheus/v1/write'
    address="http://192.168.31.14:19000/"
    url = "http://192.168.31.14:19000//v1/n9e-plus/heartbeat"
```
