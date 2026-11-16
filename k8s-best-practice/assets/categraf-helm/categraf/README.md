# Categraf Helm Chart

在 Kubernetes 集群中部署 Categraf 节点采集、Kube-State-Metrics、KSM Agent 和可选的节点清理 Operator。

## 支持的 Kubernetes 版本

```text
kubeVersion: ">=1.19.0-0 <1.38.0-0"
```

- **下限 1.19**：Chart 只使用 `v1`、`apps/v1`、`rbac.authorization.k8s.io/v1` 和 `batch/v1`（Job），这些 API 自 Kubernetes 1.9 起就已稳定，1.19 是保守的支持底线。
- **上限 `<1.38.0-0`**：跟随当前最新 Kubernetes 稳定版（v1.37.x）。客户要求保留显式上限，避免在未验证的新版本上直接安装。
- **维护规则**：Kubernetes 每发布一个新的 minor 稳定版，就需要复核并上调此上限（同步更新本节与 `Chart.yaml`）。
- **已验证范围（2026-11-03，`0.2.2-rc.1`）**：
  - 模板渲染：1.19 / 1.20 / 1.21 / 1.28 / 1.30 / 1.31 / 1.32 / 1.34 / 1.36 / 1.37 通过（Helm 3.21.3 与 Helm 4.2.3 双版本验证），1.18 与 1.38 被拒；
  - 真实集群（Kubernetes 1.28.2）：全新安装、`0.2.1` → `0.2.2-rc.1` 升级、`helm rollback`、卸载（pre-delete 清理 Hook）、重装、多 Release 隔离、Pod 自愈；
  - 1.32 以上版本未在真实集群安装验证，仅保证模板渲染通过。


## 组件

| 组件 | 工作负载 | 说明 |
|---|---|---|
| Node Agent | DaemonSet | 采集节点、kubelet、cAdvisor、kube-proxy 和主机指标 |
| Kube-State-Metrics | Deployment + Service | 暴露 Kubernetes 对象状态指标 |
| KSM Agent | StatefulSet | 采集 KSM 指标并写入 Flashcat / Nightingale |
| Operator | Deployment | 清理已删除节点在 Flashcat 上的残留设备 |

## 前置条件

- Kubernetes `>=1.19.0-0 <1.38.0-0`
- Helm 3（Helm 4.2.3 已完成 `lint` / `package` / `template` 验证）
- 可访问 Flashcat / Nightingale 服务端
- 可拉取 Chart 中配置的容器镜像
- `operator.enabled=true` 时必须提供 `operator.userToken`

## 安装示例

```bash
helm upgrade --install categraf ./categraf \
  --namespace flashcat \
  --create-namespace \
  --set categraf.serverAddr=http://flashcat.example.com:19000 \
  --set categraf.clusterName=my-cluster \
  --set operator.userToken='<token>'
```

更完整的配置见 `values.yaml`、`values-examples/values.yaml` 和 `values-examples/values.all.yaml`。

## 自定义指标标签

通过 `categraf.customLabels` 可以为所有 Categraf 上报指标追加自定义标签：

```yaml
categraf:
  customLabels:
    region: cn-shanghai
    owner: platform
```

该配置会写入 Node Agent、KSM Agent 的 `[global.labels]`，并同步写入 KSM/应用/K8s 组件抓取配置的 Prometheus `external_labels`。标签键必须符合 Prometheus 标签名规范；`env`、`cluster`、`categraf` 为保留标签，不允许覆盖。

## 少量运行时参数

Chart 只开放低风险的运行时参数，不提供任意 `config.toml` 字符串覆盖：

```yaml
categraf:
  config:
    interval: 15
  writer:
    batch: 2000          # 不配置时 Node=2000、KSM=1000
    chanSize: 1000000
  heartbeat:
    interval: 10
    timeout: 5000
    dialTimeout: 2500
```

这些参数会同时应用到 Node Agent 和 KSM Agent；`writer.batch` 未配置时保留各组件默认值。server、providers、hostname、心跳 URL 等关键结构仍由 Chart 管理。

### 指标抓取间隔

`categraf.prometheus.scrapeInterval` 控制 KSM Agent 的指标抓取周期（`kube-state-metrics`、`app-metrics`、组件指标共用），单位秒，默认 `15`：

```yaml
categraf:
  prometheus:
    scrapeInterval: 30
```

它与 `categraf.config.interval` 是两件事：后者是各 input 插件的采集周期（Node Agent 的主机/容器指标、KSM Agent 的 `[global].interval`），前者只影响 KSM Agent 按 Prometheus 协议抓取内置任务的频率。两者互不覆盖，可以分别设置。

## 应用指标自动发现

默认情况下，`appMetrics.enabled=true` 会生成 `app-metrics` Pod 发现任务：

- `app-metrics`：使用 `prometheus.io/scrape`、`prometheus.io/port`、`prometheus.io/path`、`prometheus.io/scheme` annotation。

应用身份仍使用 label：`service` 优先取 `app.kubernetes.io/name`，回退 `app`；`team` 取 `team`。

客户已有标签或 annotation、且不能修改业务 Pod 时，可通过 `appMetrics.extraScrapeConfigs` 直接追加原生 Prometheus `scrape_configs`：

```yaml
appMetrics:
  extraScrapeConfigs:
    - job_name: customer-pod-job
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          action: keep
          regex: customer-app
        - source_labels: [__meta_kubernetes_pod_ip]
          target_label: __address__
          replacement: ${1}:8080
```

`extraScrapeConfigs` 中的内容直接按 Prometheus 原生语义渲染，不引入 Chart 专用字段。

## 资源命名

- 命名空间级资源使用 `<release>-<component>`，Node Agent DaemonSet 使用 `<release>`。
- 集群级 ClusterRole 和 ClusterRoleBinding 使用 `<release>-<namespace>-<component>`。
- 所有命名空间级资源显式使用 `.Release.Namespace`。

## Release 命名与升级说明

- 命名空间级资源名使用 `<release>-<component>`，Node Agent DaemonSet 使用 `<release>`。
- Workload 和 Service selector 包含 `app.kubernetes.io/instance=<release>`。
- ClusterRole / ClusterRoleBinding 使用 `<release>-<namespace>-<component>`。
- Operator 的 leader election Lease 仍使用固定名称，本版本按“一个集群一个 Release”运行，不提供同 namespace 多 Release 的完整隔离。

> **版本号规则**：正式版本（如 `0.2.2`、`0.2.3`）才推送到 OCI 仓库并允许更新 `latest`；测试候选用预发布后缀（`0.2.2-rc.1`、`0.2.2-rc.2`…），只打版本 tag，不更新 `latest`。详见 [发布 Chart 到 OCI 仓库](../../../docs/附录/发布Chart到仓库.md)。
>
> `0.2.2`（正式版，内容等同 `0.2.2-rc.3`）在 rc.1 基础上：rc.2 修复了 `checksum/config`（改为对渲染后的配置做哈希，升级只改模板时也会自动滚动）、rc.3 修复了 `controlPlane.enabled` 下 apiserver job 的端点元标签（`__meta_kubernetes_endpoint_port_name`）。
> 
> `0.2.2-rc.1`（完整回归轮）汇总了此前未发布的三批内部构建改动：`categraf.customLabels`、annotation 应用发现 + `appMetrics.extraScrapeConfigs`、少量结构化运行时参数（`categraf.config.interval` / `writer.batch` / `writer.chanSize` / `heartbeat.*`），并修正了 `kubeVersion`（`>=1.19.0-0 <1.38.0-0`）与 `appVersion`（`0.5.32`）。生产版本仍为 `0.2.1`，可从 `0.2.1` 直接 `helm upgrade`。
>
> **升级说明（0.2.2-rc.2 起已修复）**：`checksum/config` 现在对“最终渲染出的配置 + Chart 版本 + values”整体做哈希，升级只要改变配置就会自动滚动 Pod，无需人工 `rollout restart`。
> 历史版本（≤ `0.2.2-rc.1`）的 `checksum` 只哈希 `.Values`，若升级只改模板而 values 不变，Pod 不会滚动、`subPath` 挂载的配置也不会刷新；从这些版本升级时请补执行 `kubectl -n <ns> rollout restart ds/<release> sts/<release>-ksm`。详见 `docs/测试验证记录/evidence/20261103-0.2.2-rc.1/FINDINGS.md` F1。
>
> `0.2.1` 同版本覆盖更新时曾新增 Workload selector 的 `app.kubernetes.io/instance`；由于 Deployment/StatefulSet/DaemonSet 的 selector 不可变，早期环境升级到 `0.2.1` 需执行“备份 values -> 卸载旧版本 -> 安装新版本”。全新安装不受影响。

## 镜像说明

当前版本继续使用现有镜像地址：

```text
registry.flashcat.cloud/public/...
```

暂未迁移到平台规定的 `<region.registry>/csk-component` 或 `<region.registry>/cke-init-image` 路径，作为已知规范例外保留。

## 卸载

```bash
helm uninstall categraf --namespace flashcat
```

`operator.cleanup.nodeCategraf` 和 `operator.cleanup.ksmCategraf` 默认均为 `true`。卸载前会停止对应工作负载并删除本集群设备；如需保留设备，请将对应开关改为 `false`。业务组不会被自动删除。
