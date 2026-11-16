# Categraf 0.2.3 发布前验证（接入页场景）

> 最终以 **0.2.3** 发布（2026-11-16，digest `sha256:3f1166ea…`，`latest` 同步指向 0.2.3）。

> 对应 Chart 工作区版本 `0.2.2`（未升版本号），变更两项：新增 `categraf.prometheus.scrapeInterval`、`ksmCategraf` 内存上限默认值 `1.5Gi → 2Gi`。
> 目的：验证「K8s 接入 Categraf」配置页生成的 values 在真实集群上可安装、可出数。

## 1. 环境

| 项 | 值 |
|---|---|
| 验证时间 | 2026-11-16 |
| Kubernetes | v1.28.2（kubeadm + containerd 2.2.1 + Flannel） |
| 节点 | `k8s-node1`（control-plane，NoSchedule taint）、`k8s-node2` |
| 集群访问 | Tailscale `100.98.231.109`（文档原记录 `100.89.123.71` 已失效） |
| Flashcat | `http://192.168.31.14:19000`（集群内）/ `http://100.73.244.81:19000`（Tailscale） |
| 指标查询 | VictoriaMetrics vmselect `http://100.73.244.81:8481/select/0/prometheus/api/v1/query` |
| 部署方式 | 独立 release `categraf-verify`（ns 同名），连续多次 upgrade；另对既有 `categraf` release 做升级验证 |

## 2. 变更点

| 文件 | 变更 |
|---|---|
| `templates/_config.tpl` | `scrape_interval: 15s` → `{{ int (default 15 (dig "prometheus" "scrapeInterval" 0 .Values.categraf)) }}s` |
| `values.yaml` | 新增 `categraf.prometheus.scrapeInterval: 15`；`ksmCategraf.resources.limits.memory` `1.5Gi → 2Gi` |
| `values-examples/values.all.yaml`、`README.md` | 注释与文档同步 |

## 3. 场景验证（指标均从 VM 实际查得）

### 3.1 两者都要 + 自定义规则 + scrapeInterval 60

| 检查 | 结果 |
|---|---|
| Pod | 2 DS（两节点）+ ksm + kube-state-metrics + operator 全 Running |
| 配置 | `scrape_interval: 60s`；job = ksm / `annotated-test`（自定义）/ coredns，无 `app-metrics`（defaultJob 关闭） |
| 资源 | KSM `500m/512Mi → 1000m/2Gi` |
| **指标** | `up{job="annotated-test", service="annotated-metrics-test"}=1`、`kube-state-metrics=1`、`coredns=1`、`kubelet=1`（含 `/metrics/cadvisor`）、`kube-proxy=1`；`node_load1{instance="k8s-node1/2"}` 有值 |

**自定义抓取规则、cadvisor、kubelet、kube-proxy、node_exporter 全部确认出数。**

### 3.2 仅 DaemonSet + 非特权模式 + 自定义资源

| 检查 | 结果 |
|---|---|
| 工作负载 | 仅 DS + operator；ksm / kube-state-metrics 已移除 |
| 安全上下文 | `privileged=false`、`allowPrivilegeEscalation=false`、`drop ALL + add SYSLOG` |
| 命令通道 | `CATEGRAF_HOST_EXEC_PROFILE=false`，无 ibex 挂载 |
| 资源 | requests `300m/600Mi`（部分覆盖生效），limits 保持 Chart 默认 `1/2Gi` |

### 3.3 仅 StatefulSet + 应用指标 + 控制平面 + scrapeInterval 30

| 检查 | 结果 |
|---|---|
| 工作负载 | DaemonSet 全删；ksm + kube-state-metrics + operator Running |
| 配置 | `scrape_interval: 30s` |
| **指标** | `app-metrics=1`、`kube-state-metrics=1`、`coredns=1`、**`apiserver=1`**；`etcd=0`、`kube-controller-manager=0`、`kube-scheduler=0` |

**控制平面的实测结论**：`apiserver` 走 `default/kubernetes` Service，无需任何改动即可采；其余三个走组件自身端口，必须放开监听（`--bind-address=0.0.0.0`、etcd `--listen-metrics-urls`），否则稳定 `up=0`——与页面提示一致。

### 3.4 仅 DaemonSet + 设备标识加集群前缀

| 检查 | 结果 |
|---|---|
| 渲染 | `hostname = "${CLUSTER_NAME}-${HOSTNAME}"` |
| 设备 | 新增 `k8s-verify-d-k8s-node1/2`（`target_up=2`）；原有 `k8s-node1/2` 不受影响 |

**结论**：默认 `ident=节点名` 时同集群多 release 会互相覆盖设备；「设备标识=集群名-节点名」可规避。

### 3.5 既有 release 升级（旧 0.2.2 → 新 0.2.2）

| 检查 | 结果 |
|---|---|
| 命令 | `helm upgrade categraf /root/categraf-0.2.2.tgz -f <备份 values>`，revision 10 → 11 |
| manifest 差异 | 共 16 行：3 处 `checksum/config` + 1 处 `memory: 1.5Gi → 2Gi`，其余无变化 |
| 滚动 | DS / KSM / operator 全部重启就绪 |
| 指标 | 升级后 `kube-state-metrics=1`、`app-metrics=1` 持续正常 |

### 3.6 卸载 + 设备自动清理

| 检查 | 结果 |
|---|---|
| 前置 | `operator.enabled=true` + `cleanup.node/ksmCategraf=true`，cluster `k8s-verify-e`，设备 `k8s-verify-e-k8s-node1/2` 已在线 |
| 卸载 | `helm uninstall categraf-verify -n categraf-verify --wait` → `release "categraf-verify" uninstalled` |
| 清理 | 卸载后 `/api/n9e/targets` 中 `k8s-verify-e-*` **已全部删除**；namespace 无残留资源 |

> 首次尝试时误用了失效 token，hook 报 `401` 并持续重试（`waitHeartbeatsStopped` 失败），说明 token 无效时清理不会误删设备，行为安全。

## 4. 未覆盖 / 已知问题

| 项 | 说明 |
|---|---|
| 离线镜像覆盖 | 测试环境无内网 registry，只验证 values 生成与命令，未实际拉取镜像 |
| 网络插件采集 | 测试集群为 Flannel，只有「不采集」路径 |
| **syslog 插件未被真正禁用** | DS 日志持续 `collector failed name syslog`；旧 release 同样 14 条，属 0.2.2 既有问题：空 ConfigMap 覆盖 `input.opensyslog` 目录只清空配置，插件仍以默认参数运行 |
| 遗留测试设备 | `k8s-verify-a/c/d` 的少量设备因当时 cleanup=false 未删，已 `up=0`，可手工清理 |

### 3.7 发布与线上拉取验证

| 检查 | 结果 |
|---|---|
| 推送 | `helm push categraf-0.2.3.tgz oci://registry.flashcat.cloud/public/charts` → digest `sha256:3f1166eafcc6cde19d7585fc8ebea67f7474c67eac6c038a147baf31ee4d9106` |
| latest | `oras copy …:0.2.3 …:latest`，`helm show chart` 不带版本返回 `version: 0.2.3` |
| 从仓库安装 | 测试集群 `helm upgrade` 用 `oci://…--version 0.2.3` 成功，revision 12，DS 标签 `categraf-0.2.3` |
| 升级后指标 | VM 查询 `kube-state-metrics=1`、`app-metrics=1`，集群 `up` 序列共 10 条 |

## 5. 结论

页面各开关（采集模式 / 资源规格 / 自定义规则 / 非特权模式 / 应用指标 / 控制平面 / 设备标识 / 卸载清理）生成的 values 在 v1.28.2 上全部可用，且**指标级验证通过**（VM 实际查询 `up` 与 `node_load1`）；`scrapeInterval` 三种取值生效；KSM 内存默认值 2Gi 生效；升级仅改内存与 checksum；卸载清理能正确删除本集群设备。

遗留：`syslog` 插件禁用逻辑无效（既有问题），建议单独修复。
