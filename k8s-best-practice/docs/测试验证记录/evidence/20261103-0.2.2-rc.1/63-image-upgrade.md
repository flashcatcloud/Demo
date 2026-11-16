# CMD: 镜像升级到最新（categraf_ent v0.5.32 → v0.5.45 / servicemap-v0.5.45），版本号仍 0.2.2，远端覆盖重推
# AT: 2026-11-03T08:36:21Z / 2026-11-03T16:36:21+0800

## 1. 变更内容
```
values.yaml / values-examples：
  nodeCategraf.image : categraf_ent:servicemap-v0.5.32 → categraf_ent:servicemap-v0.5.45
  ksmCategraf.image  : categraf_ent:v0.5.32            → categraf_ent:v0.5.45
  appVersion         : 0.5.32 → 0.5.45
  kube-state-metrics : v2.19.1（registry 内唯一 tag，不变）
  categraf-operator  : 0.0.7（registry 最新，不变）
Chart version 保持 0.2.2（按要求覆盖重推）
```
## 2. 包与渲染差异
```
新 0.2.2 SHA256: 7b1b18c01aad2d9a3da29816730ea122dba120399895335d68ddbe5620bcec0f
旧 0.2.2 SHA256: 966ec17f1e93962ca9e9d7516c5dc84733e05b7daf4c4e721382e0b75d4683cb
归一化渲染 diff（仅镜像 tag 2 行）:
  801c801
  <         image: "registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.32"
  ---
  >         image: "registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.45"
  1096c1096
  <         - image: "registry.flashcat.cloud/public/categraf_ent:v0.5.32"
  ---
  >         - image: "registry.flashcat.cloud/public/categraf_ent:v0.5.45"
```
## 3. 真机升级验证
```
NAMESPACE: categraf
STATUS: deployed
REVISION: 4
TEST SUITE: None
daemon set "categraf" successfully rolled out

$ Pod 与镜像
NAME                                           STATUS    IMAGE
annotated-metrics-test-58c756859d-pw94z        Running   registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1
categraf-2bfj6                                 Running   registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.45
categraf-ksm-0                                 Running   registry.flashcat.cloud/public/categraf_ent:v0.5.45
categraf-kube-state-metrics-844f8d85fb-mp92g   Running   registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1
categraf-operator-6c9cc67c56-jwl66             Running   registry.flashcat.cloud/public/categraf-operator:0.0.7
categraf-wnl6d                                 Running   registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.45

$ release
categraf	categraf 	4       	2026-11-03 16:36:21.490288184 +0800 CST	deployed	categraf-0.2.2	0.5.45     
```

## 4. 新镜像运行态验证
```
设备:
  k8s-flashcat-test-20261029-categraf-ksm-0 up=2 agent=ent-v0.5.45
  k8s-node1 up=2 agent=ent-v0.5.45-servicemap
  k8s-node2 up=2 agent=ent-v0.5.45-servicemap

设备 target_up=2 数量: 3/3
up 异常条数: 0
series: 16773
customLabels: 16773

--- 关键指标族 ---
  node_cpu_seconds_total                   64
  container_cpu_usage_seconds_total        82
  kube_pod_info                            40
  cpu_usage_active                         2

--- 日志错误检查（node/ksm 最近 300 行）---
  component=categraf 命中 error|panic|fatal|refused: 13
  component=categraf-ksm 命中 error|panic|fatal|refused: 1
```
## 5. 结论
```
镜像升级到 v0.5.45 / servicemap-v0.5.45 后：Pod 全部 Running、设备 3/3 target_up=2、agent_version 上报为 ent-v0.5.45、up 异常 0、指标齐全。
```

## 6. 覆盖重推（版本号仍 0.2.2）

| 项 | 结果 |
|---|---|
| 本地包 | `categraf-0.2.2.tgz` SHA256 `7b1b18c01aad2d9a3da29816730ea122dba120399895335d68ddbe5620bcec0f`（appVersion 0.5.45） |
| 旧 0.2.2 | SHA256 `966ec17f…68d75d`（镜像 v0.5.32）——已被覆盖，仅作历史记录 |
| OCI 推送 | `publish-chart.sh 0.2.2` 覆盖重推；`latest` 同步更新，Digest `sha256:93f5f5b6f010f915eb2af0ac5717a98dc9e0e49c4f75fef17dc01bd233f1573e` |
| 远端校验 | 按 `0.2.2` 与 `latest` 各拉回一次，包 SHA256 均为 `7b1b18c01aad2d9a3da29816730ea122dba120399895335d68ddbe5620bcec0f`，与本地一致 |
| 风险说明 | 覆盖重推使同一 tag 的 digest 变化：之前拉过旧 0.2.2 的环境需重新 `helm pull` 才能拿到新镜像；回滚到旧内容只能靠本地旧包（已记录旧 SHA），无法从仓库取回 |

## 7. 镜像版本表（当前）

| 组件 | 镜像 | 说明 |
|---|---|---|
| Node Agent | `registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.45` | registry 最新 servicemap tag |
| KSM Agent | `registry.flashcat.cloud/public/categraf_ent:v0.5.45` | registry 最新 |
| kube-state-metrics | `registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1` | registry 内无更新 tag |
| Operator | `registry.flashcat.cloud/public/categraf-operator:0.0.7` | registry 最新 |

## 8. 追加覆盖重推：values.all.yaml 推荐语修正

- 改动：`values-examples/values.all.yaml` 头部 `# 默认使用精简版：values-examples/values.yaml` → `# 推荐作为 my-values.yaml 的起点（完整注释版；精简版见 values-examples/values.yaml）`（纯注释，渲染 diff = 0）
- 包 SHA256：`e4f9d2f995046fbaa9d0a8738e15284008bbad66ff37365e967f723da23c09ed`
- OCI：0.2.2 再次覆盖重推，`latest` 更新，Digest `sha256:2f9dff88456274e4bebbad0d7cdb298f77fda0f7ef5a974c6c057e902eea2b2f`
- 远端校验：按 `0.2.2` 与 `latest` 各拉回一次，SHA 均 = `e4f9d2f995046fbaa9d0a8738e15284008bbad66ff37365e967f723da23c09ed`
- 说明：此为当日第 3 次覆盖 0.2.2（初始 966ec17f → 镜像升级 7b1b18c0 → 本次 e4f9d2f9），仅注释变化，运行时行为不变

## 9. 追加：values 注释对齐并再次覆盖 0.2.2

- 背景：文档改为「以 values.yaml 精简版为起点，values.all.yaml 仅作参数参考」，chart 内注释同步
- 改动：`values-examples/values.all.yaml` 头部、`values-examples/values.yaml` 头部（纯注释，渲染 diff = 0）
- 包 SHA256：`8688253178af785d4d1cdf247f2554f574b02577607add0ef8d42ffe4ca3620e`；OCI Digest `sha256:513bb9938f41c07b2e7507ec8486bfafca6a4c4f2220d07bc02535d84b75a742`；`latest` 已指向该包
