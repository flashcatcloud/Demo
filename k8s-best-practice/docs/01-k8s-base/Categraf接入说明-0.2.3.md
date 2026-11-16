# Categraf 接入说明（Kubernetes）

> 适用 Chart `0.2.3`｜Categraf `0.5.45`｜2026-11-16
> 本文可直接粘贴到钉钉文档；命令与参数均来自 Chart 实际渲染结果，并在 Kubernetes v1.28.2 上验证。

---

## 1. 适用范围与架构

Chart 一次安装会在集群里创建 4 个工作负载，各自独立开关：

| 工作负载 | 类型 | 作用 | 开关 |
|---|---|---|---|
| Node Agent | DaemonSet | 每节点一个，采集主机指标、kubelet/cAdvisor、kube-proxy | `nodeCategraf.enabled` |
| KSM Agent | StatefulSet | 单副本，采集 KSM 指标、应用指标、K8s 组件 | `ksmCategraf.enabled` |
| kube-state-metrics | Deployment | 暴露 K8s 对象状态指标 | `kubeStateMetrics.enabled` |
| categraf-operator | Deployment | 节点删除/卸载后清理 Flashcat 上的残留设备 | `operator.enabled` |

### 能力边界

| 数据 | DaemonSet | StatefulSet |
|---|---|---|
| 主机指标、kubelet/cAdvisor、kube-proxy | ✅ | ❌ |
| KSM 指标、应用指标、CoreDNS/Calico/Cilium | ❌ | ✅ |
| 服务拓扑、命令通道 | ✅ | ❌ |

两种模式能力不重叠，**建议同时部署**（同一 Release 里两个开关都开）。

---

## 2. 环境要求

| 项 | 要求 |
|---|---|
| Kubernetes | **1.19 ~ 1.37**（1.19 以下未验证；1.38 及以上会被 Helm 直接拒绝） |
| Helm | ≥ 3.0 |
| 节点 | Linux；DaemonSet 需要 `hostNetwork`、`hostPID`、`privileged` |
| Pod Security | 命名空间不能是 `baseline`/`restricted`，建议 `privileged` |
| 网络 | 节点能访问 Flashcat 服务地址（默认端口 19000），无需开放入向端口 |
| 权限 | 需要创建 ClusterRole / ClusterRoleBinding |

检查命令：

```bash
kubectl version --short
helm version --short
kubectl get nodes --no-headers | wc -l    # 部署后 DS 副本数应等于它
```

> 不满足上述要求时，请联系 Flashcat 技术人员。

---

## 3. 依赖与物料

| 依赖 | 版本 | 说明 |
|---|---|---|
| Chart | `0.2.3` | `oci://registry.flashcat.cloud/public/charts/categraf` |
| 节点镜像 | `categraf_ent:servicemap-v0.5.45` | 含服务拓扑能力 |
| 集群镜像 | `categraf_ent:v0.5.45` | 与节点镜像**不是同一个 tag** |
| KSM 镜像 | `kube-state-metrics:v2.19.1` | KSM 指标的数据源 |
| Operator 镜像 | `categraf-operator:0.0.7` | 仅开启 Operator 时需要 |

镜像版本可在页面参数里调整；调整后 Chart 会显式覆盖 `*.image`，未调整则沿用 Chart 默认值。

---

## 4. 在线安装

```bash
# 1) 准备 values.yaml（见第 6 节）
# 2) 安装
helm upgrade --install categraf \
  oci://registry.flashcat.cloud/public/charts/categraf \
  --version 0.2.3 \
  -n flashcat --create-namespace \
  -f values.yaml

# 3) 检查
kubectl -n flashcat get ds categraf
kubectl -n flashcat get sts categraf-ksm
kubectl -n flashcat get pods -o wide
```

---

## 5. 离线安装

### 5.1 同步 Chart（在可联网机器执行）

```bash
helm pull oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.3

# 可选：推送到内网 OCI 仓库
helm registry login <内网仓库地址>
helm push categraf-0.2.3.tgz oci://<内网仓库地址>/charts
```

### 5.2 同步镜像

方式一：docker（通用）

```bash
docker login <内网仓库地址>

docker pull registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.45
docker tag  registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.45 <前缀>/categraf_ent:servicemap-v0.5.45
docker push <前缀>/categraf_ent:servicemap-v0.5.45

# 集群镜像、KSM 镜像、Operator 镜像同理，共 3~4 个
```

方式二：skopeo（无需本地存储，支持多架构）

```bash
skopeo login <内网仓库地址>
# 内网仓库是 HTTP 或自签证书时，给每条 copy 加 --dest-tls-verify=false
skopeo copy --all \
  docker://registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.45 \
  docker://<前缀>/categraf_ent:servicemap-v0.5.45
```

> `docker pull` 只拉当前机器架构；多架构集群用 `--platform` 分别拉取，或直接用 `skopeo copy --all`。

### 5.3 安装

```bash
helm upgrade --install categraf ./categraf-0.2.3.tgz \
  -n flashcat --create-namespace \
  -f values.yaml
```

values 中需要用镜像前缀覆盖：

```yaml
nodeCategraf:
  image: "<前缀>/categraf_ent:servicemap-v0.5.45"
ksmCategraf:
  image: "<前缀>/categraf_ent:v0.5.45"
kubeStateMetrics:
  image: "<前缀>/kube-state-metrics/kube-state-metrics:v2.19.1"
operator:
  image: "<前缀>/categraf-operator:0.0.7"
```

---

## 6. 配置说明

### 6.1 必填参数

| 参数 | values 键 | 说明 |
|---|---|---|
| Flashcat 地址 | `categraf.serverAddr` | 如 `http://flashcat.internal:19000` |
| 集群名 | `categraf.clusterName` | 同一 Flashcat 下必须**全局唯一**，写入 `cluster` 标签 |
| 命名空间 | `-n` | 建议 `flashcat` |
| API Token | `operator.userToken` | `operator.enabled=true` 时必填 |

### 6.2 常用可选参数

| 参数 | values 键 | 默认 | 说明 |
|---|---|---|---|
| 环境标签 | `categraf.env` | — | 写入 `env` 标签，如 prod/test |
| 业务组 | `categraf.heartbeatGid` | 空 | 设备心跳自动归入该业务组 |
| 自定义标签 | `categraf.customLabels` | 空 | 附加到所有上报指标；`env`/`cluster`/`categraf` 为保留键 |
| 采集间隔 | `categraf.config.interval` | 15 | 各 input 插件的采集周期 |
| 指标抓取间隔 | `categraf.prometheus.scrapeInterval` | 15 | **0.2.3 新增**：KSM/应用/组件指标的抓取周期 |
| 写入批量 | `categraf.writer.batch` | 2000/1000 | 大集群写入积压时调大 |
| 设备标识 | `nodeCategraf.hostname` | `nodeName` | 服务拓扑要求用节点名；多集群可改 `${cluster}-${nodeName}` |

> `config.interval` 与 `prometheus.scrapeInterval` 是两件事：前者是插件采集周期，后者是 Prometheus 协议抓取周期。

### 6.3 采集开关

| 开关 | 默认 | 说明 |
|---|---|---|
| `nodeCategraf.inputs.cadvisor` | true | 容器 + kubelet 指标 |
| `nodeCategraf.inputs.nodeExporter` | true | 主机指标（node_exporter 插件） |
| `nodeCategraf.inputs.hostNative.enabled` | true | 原生主机插件，Flashcat 主机大盘默认匹配这套 |
| `kubeProxy.enabled` | true | 由 Node Agent 采集 127.0.0.1:10249 |
| `ksmCategraf.jobs.kubeStateMetrics` | true | KSM 指标 |
| `appMetrics.defaultJob.enabled` | true | 按 `prometheus.io/*` 注解自动发现应用 |
| `coreDns.enabled` | true | CoreDNS 指标 |
| `networkPlugin.calico/cilium.enabled` | 按集群 | 二选一，选错会产生 `up=0` 无效目标 |
| `controlPlane.enabled` | false | 控制平面指标，见第 10 节 |

### 6.4 完整 values 示例

```yaml
categraf:
  serverAddr: "http://flashcat.internal:19000"
  clusterName: "prod-k8s-01"
  env: "prod"
  heartbeatGid: "2"
  config:
    interval: 15
  prometheus:
    scrapeInterval: 30
  # customLabels:
  #   region: "cn-shanghai"

operator:
  enabled: true
  userToken: "<FLASHCAT_USER_TOKEN>"
  cleanup:
    nodeCategraf: true
    ksmCategraf: true

nodeCategraf:
  enabled: true
  hostname: nodeName
  inputs:
    cadvisor: true
    hostNative:
      enabled: true

ksmCategraf:
  enabled: true
  replicas: 1

kubeStateMetrics:
  enabled: true

appMetrics:
  enabled: true
  defaultJob:
    enabled: true
  # extraScrapeConfigs:
  #   - job_name: redis-exporter
  #     kubernetes_sd_configs:
  #       - role: endpoints

kubeProxy:
  enabled: true
coreDns:
  enabled: true
networkPlugin:
  calico:
    enabled: false
  cilium:
    enabled: false
controlPlane:
  enabled: false
```

### 6.5 应用指标采集的两种方式

**方式一：注解自动发现（推荐）** —— 业务侧给 Pod 加注解：

```yaml
metadata:
  labels:
    app: order-service
    team: platform
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"        # 容器端口
    prometheus.io/path: "/metrics"    # Spring Boot 用 /actuator/prometheus
```

**方式二：自定义抓取规则** —— 不能改注解的中间件，用原生 `scrape_configs`：

```yaml
appMetrics:
  extraScrapeConfigs:
    - job_name: redis-exporter
      kubernetes_sd_configs:
        - role: endpoints
      relabel_configs:
        - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name]
          action: keep
          regex: middle;redis-exporter
```

> 两种方式可以并存；同一个 target 只走一条路径，否则会产生重复时间线。

---

## 7. 接入校验

### 7.1 集群侧

```bash
kubectl -n flashcat get ds categraf          # READY = 节点数
kubectl -n flashcat get sts categraf-ksm     # 1/1
kubectl -n flashcat get pods -o wide
kubectl -n flashcat logs ds/categraf --tail=50
```

### 7.2 平台侧

| 检查 | 期望 |
|---|---|
| 设备列表 | 出现 `<集群名>-<节点名>` 或节点名，`target_up = 2` |
| 主机指标 | `node_load1{cluster="<集群名>"}` 有数据 |
| 容器指标 | `container_cpu_usage_seconds_total{cluster="<集群名>"}` 有数据 |
| KSM | `kube_pod_status_phase{cluster="<集群名>"}` 有数据 |
| 应用 | `up{job="app-metrics"}` 或自定义 job `up{job="<job名>"}` = 1 |

---

## 8. 升级与回滚

```bash
# 备份当前 values
helm -n flashcat get values categraf > categraf-values.backup.yaml

# 升级
helm upgrade categraf \
  oci://registry.flashcat.cloud/public/charts/categraf \
  --version 0.2.3 -n flashcat -f values.yaml

# 观察滚动
kubectl -n flashcat rollout status ds/categraf
kubectl -n flashcat rollout status sts/categraf-ksm

# 回滚
helm rollback categraf <REVISION> -n flashcat
```

> 0.2.2 起 checksum 基于渲染后的配置，改 values 或升级会自动滚动 Pod。从 0.2.1 升级且 values 未变更时，需补一次 `kubectl rollout restart ds/categraf sts/categraf-ksm -n flashcat`。

---

## 9. 卸载

```bash
# 默认：卸载工作负载并清理本集群在 Flashcat 上的设备
helm uninstall categraf -n flashcat --wait

# 只删工作负载、保留设备
helm uninstall categraf -n flashcat --no-hooks
```

清理行为由 `operator.cleanup.nodeCategraf` / `ksmCategraf` 控制（默认均为 true）：

- 只作用于**本集群**（按集群名匹配），不会删除业务组，也不影响其他集群
- 卸载时先停采集、等设备心跳停止，再删除设备
- Token 无效或 Flashcat 不可达时，清理会失败并重试，**不会误删设备**；确认要强删用 `--no-hooks`

---

## 10. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| Pod `ImagePullBackOff` | 镜像前缀或版本参数不对；离线环境确认镜像已同步到内网仓库 |
| DS 副本数少于节点数 | 节点有 `NoExecute` taint、PSA 限制、或资源不足；看 `kubectl describe pod` |
| 设备一直离线 | 节点到 Flashcat 地址不通；检查 `serverAddr` 与网络策略 |
| `up{job="app-metrics"} = 0` | 业务 Pod 未加 `prometheus.io/scrape: "true"`，或端口/路径写错（要容器端口） |
| 自定义 job 无数据 | `relabel_configs` 未匹配上；用 `helm template` 或平台的目标列表确认 |
| `controlPlane` 部分 `up=0` | apiserver 开箱可采；scheduler/controller-manager/etcd 需放开监听（`--bind-address=0.0.0.0`、etcd `--listen-metrics-urls`） |
| 多 Release 设备互相覆盖 | 默认 ident 是节点名；同一集群装多个 Release 时把 `nodeCategraf.hostname` 改为 `${cluster}-${nodeName}` |
| 日志持续报 `collector failed name syslog` | 0.2.3 已知问题：syslog 插件未被真正禁用，不影响指标采集 |

---

## 附：版本变更（0.2.2 → 0.2.3）

| 项 | 变更 |
|---|---|
| 新增参数 | `categraf.prometheus.scrapeInterval`（默认 15），指标抓取间隔可配 |
| 默认值调整 | `ksmCategraf.resources.limits.memory` 1.5Gi → 2Gi |
| 发布信息 | digest `sha256:3f1166ea…`，`latest` 已指向 0.2.3 |
