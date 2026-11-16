# CMD: G6 package：包内容一致性、Helm 3/4 双版本、发布脚本守卫
# AT: 2026-11-03T07:34:41Z / 2026-11-03T15:34:41+0800

## 6.1 包内容 vs 仓库目录（解包后逐文件 diff）
```
说明：helm package 会重新序列化 Chart.yaml（键排序、注释丢失），因此对 Chart.yaml 比较语义、其余文件比较字节
$ helm show chart <解包目录> vs <包>
(Chart.yaml 语义一致)
$ diff -r（排除 Chart.yaml）
(其余文件完全一致)

$ tar tzf 文件数
包内文件: 14
categraf/Chart.yaml
categraf/values.yaml
categraf/templates/_config.tpl
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
## 6.2 helm show values vs 仓库 values.yaml
```
(一致，忽略尾部空行差异)
```
## 6.3 测试主机 Helm 3.21.3：lint + kubeVersion 矩阵
```
remote helm: v3.21.3+g1ad6e68
$ helm lint（远端解包目录）

1 chart(s) linted, 0 chart(s) failed

$ kubeVersion 矩阵（Helm 3.21.3）
  1.18.0  REJECT  Error: chart requires kubeVersion: >=1.19.0-0 <1.38.0-0 which is incompatible with Kuberne
  1.19.0  OK
  1.28.2  OK
  1.32.0  OK
  1.36.0  OK
  1.37.2  OK
  1.38.0  REJECT  Error: chart requires kubeVersion: >=1.19.0-0 <1.38.0-0 which is incompatible with Kuberne
```
## 6.4 publish-chart.sh 守卫（helm/oras/crane 全部 stub，不触网）
```
$ ./publish-chart.sh 0.2.2-rc.1   # 预发布版本
==> 预发布版本 0.2.2-rc.1：不更新 latest（latest 保持指向生产版本）
==> 推送 categraf-0.2.2-rc.1.tgz -> oci://registry.flashcat.cloud/public/charts
[stub-helm] push categraf-0.2.2-rc.1.tgz oci://registry.flashcat.cloud/public/charts
==> 验证
[stub-helm] show chart oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.2-rc.1
（预发布版本不打 latest；GA 时用正式版本号再推一次，由那次更新 latest）
推送完成: oci://registry.flashcat.cloud/public/charts/categraf:0.2.2-rc.1

$ ./publish-chart.sh 0.2.1       # 正式版本（应触发 latest）
==> 推送 categraf-0.2.1.tgz -> oci://registry.flashcat.cloud/public/charts
[stub-helm] push categraf-0.2.1.tgz oci://registry.flashcat.cloud/public/charts
==> 验证
[stub-helm] show chart oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1
==> 打 latest 标签（oras）
[stub-oras] copy registry.flashcat.cloud/public/charts/categraf:0.2.1 registry.flashcat.cloud/public/charts/categraf:latest
推送完成: oci://registry.flashcat.cloud/public/charts/categraf:0.2.1
```
## 6.5 Chart 中引用的镜像（与测试记录/文档核对）
```
registry.flashcat.cloud/public/categraf-operator:0.0.7
registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.32
registry.flashcat.cloud/public/categraf_ent:v0.5.32
registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1
```
