# K8S 指标采集

在 Kubernetes 集群中部署 Categraf，采集节点、Kubernetes 对象、组件与应用指标，统一上报至 Flashcat / Nightingale。Chart 包含 Node Agent（DaemonSet）、KSM Agent（StatefulSet）、kube-state-metrics（Deployment）与可选的节点清理 Operator。

适用版本 0.2.3 ｜ 更新日期 2026-11-16

## 1 前置条件

- Kubernetes 1.19 – 1.37（1.28.2 实机验证），本机已安装 Helm 3
- 已部署 Flashcat / Nightingale，提供服务端地址与业务组 GID
- 集群可拉取 registry.flashcat.cloud 镜像；内网环境见 2.4

## 2 部署

### 2.1 拉取 Chart

```bash
helm pull oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.3
tar xvf categraf-0.2.3.tgz
```

> **说明**：0.2.3 为当前正式版，latest 同样指向该版本。

### 2.2 配置 values

以精简版 values.yaml 为起点，只保留常用项，其余沿用 Chart 默认值：

```bash
cp categraf/values-examples/values.yaml my-values.yaml
```

必填项：

- `categraf.serverAddr`：Flashcat 服务端地址
- `categraf.clusterName`：集群名，必须全局唯一，每个 Kubernetes 集群使用不同值
- `operator.userToken`：Flashcat API Token；不需要节点清理时可将 `operator.enabled` 设为 false

常用可选项：`categraf.heartbeatGid`（业务组 GID）、`categraf.env`（环境标签）、`categraf.customLabels`（附加到所有上报指标的自定义标签）、`categraf.prometheus.scrapeInterval`（集群侧抓取周期，默认 15 秒）、`controlPlane.enabled`（采集控制平面指标，默认 false，见附录 A）。

最小配置示例：

```yaml
categraf:
  serverAddr: "http://10.8.112.10:19000"   # 必填：Flashcat 服务端地址
  clusterName: "Kubernetes-cluster"         # 必填：集群名，必须全局唯一
  env: "test"                               # 可选：环境标签，如 prod / test
  heartbeatGid: "2"                         # 可选：业务组 GID
  # customLabels:                           # 可选：附加到所有上报指标的自定义标签
  #   region: "cn-shanghai"
  #   owner: "platform"
operator:
  enabled: true
  userToken: "your-flashcat-token"          # 必填：Flashcat API Token

appMetrics:
  enabled: true
  # 只保留自定义采集任务时，关闭内置 prometheus.io/* 采集
  # defaultJob:
  #   enabled: false
```

> **说明**：镜像、资源规格与各采集任务开关均有注释说明，按需修改；完整参数参考见附录 B，只复制需要的片段，不要整体覆盖。

### 2.3 安装与检查

```bash
helm upgrade --install categraf ./categraf -n flashcat --create-namespace -f my-values.yaml
kubectl get pods -n flashcat -o wide
```

部署后确认：

- Node Agent 的 Pod 数量等于节点数量
- KSM Agent、kube-state-metrics、Operator 各 1 个 Pod，状态均为 Running
- Flashcat 集群列表中出现该集群，设备在线

### 2.4 内网部署（可选）

集群可直接访问 registry.flashcat.cloud 时，本节可跳过。

先将以下镜像同步至内网仓库：

```text
registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.45
registry.flashcat.cloud/public/categraf_ent:v0.5.45
registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1
registry.flashcat.cloud/public/categraf-operator:0.0.7
```

再在 my-values.yaml 中覆盖镜像地址，内网仓库地址替换为实际地址：

```yaml
nodeCategraf:
  image: "内网仓库地址/categraf_ent:servicemap-v0.5.45"
ksmCategraf:
  image: "内网仓库地址/categraf_ent:v0.5.45"
kubeStateMetrics:
  image: "内网仓库地址/kube-state-metrics:v2.19.1"
operator:
  image: "内网仓库地址/categraf-operator:0.0.7"
```

> **注意**：镜像版本需与 Chart 默认版本保持一致，并覆盖节点架构（linux/amd64 或 linux/arm64）。

## 3 应用指标采集（自动发现）

KSM Agent 内置 Prometheus，基于 Kubernetes Pod 自动发现抓取目标：只抓取带 prometheus.io/scrape 注解的 Pod（Prometheus 社区通用约定），默认抓取间隔 15 秒，无需逐个配置目标。

### 3.1 注解说明

- `prometheus.io/scrape`：必填，固定为 true，否则不抓取
- `prometheus.io/port`：必填，容器端口，不是 Service 端口
- `prometheus.io/path`：可选，指标路径，默认 /metrics；Spring Boot 为 /actuator/prometheus
- `prometheus.io/scheme`：可选，http（默认）或 https

### 3.2 配置示例

在业务 Deployment 的 spec.template.metadata 中添加标签与注解：

```yaml
metadata:
  labels:
    app: order-service     # 映射为指标标签 service
    team: platform         # 映射为指标标签 team
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
    prometheus.io/scheme: "http"
```

抓取到的指标自动附带 service（取自 Pod 标签 app 或 app.kubernetes.io/name）、team（取自 Pod 标签 team）、namespace、pod，以及集群级标签 cluster、env、customLabels。

### 3.3 无法修改业务 Pod 时

存量 Pod 不能修改标签或不能重启时，使用原生 Prometheus 采集规则，只新增采集任务，不修改业务 Pod。如需完全关闭内置 prometheus.io/* 采集任务、只保留自定义任务，设置 `appMetrics.defaultJob.enabled: false`（0.2.2 起）：

```yaml
appMetrics:
  extraScrapeConfigs:
    - job_name: customer-custom-job
      kubernetes_sd_configs:
        - role: pod
          namespaces:
            names: [order]
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_existing_label]
          action: keep
          regex: "true"
        - source_labels: [__meta_kubernetes_pod_ip, __meta_kubernetes_pod_annotation_existing_port]
          target_label: __address__
          regex: (.+);(\d+)
          replacement: "${1}:${2}"
```

### 3.4 验证与排查

- 验证：在 Flashcat 查询 up{job="app-metrics"}，值为 1 表示抓取成功；指标应包含 service、team 标签
- 无抓取目标：确认 Pod 已设置 prometheus.io/scrape 注解，且值为 true
- up 值为 0：确认 prometheus.io/port 为容器端口，prometheus.io/path 与实际暴露路径一致
- 修改后未生效：修改 Pod 注解会触发滚动重启，待新 Pod 就绪后重新验证
- 连接被拒绝：存在 NetworkPolicy 时，需放通 flashcat 命名空间到业务 Pod 的指标端口

## 4 组件采集（可选）

- `coreDns.enabled`：默认 true，采集 CoreDNS 指标
- `kubeProxy.enabled`：默认 true，采集 kube-proxy 指标
- `networkPlugin.calico.enabled`、`networkPlugin.cilium.enabled`：默认 true，采集对应网络插件指标
- `controlPlane.enabled`：默认 false，采集控制平面指标，配置方法见附录 A

按集群实际使用的组件保留对应开关，未使用的组件建议设为 false。

## 5 升级、回滚与卸载

```bash
# 升级
helm upgrade --install categraf ./categraf -n flashcat --create-namespace -f my-values.yaml

# 回滚
helm rollback categraf REVISION -n flashcat

# 卸载
helm uninstall categraf -n flashcat --wait
```

> **升级说明**：0.2.2 起 checksum 基于渲染后的配置，升级会自动滚动 Pod 加载新配置。从 0.2.1 或 0.2.2-rc.1 升级且 values 未变更时，旧版本不会自动刷新配置，需补充执行 kubectl rollout restart ds/categraf sts/categraf-ksm -n flashcat。

> **卸载说明**：operator.cleanup.nodeCategraf 与 operator.cleanup.ksmCategraf 默认均为 true，卸载会先停止采集、等待心跳停止后删除本集群在 Flashcat 上的设备；如需保留设备，请将上述开关设为 false。清理仅作用于本集群，不影响其它集群，也不会删除业务组。

## 附录 A 控制平面采集

控制平面指标支持两种采集方式：

- 自动发现：适用于 kubeadm 集群（控制平面为 Static Pod），需先放开组件监听地址
- 远程下发：kubeadm 与二进制部署均适用，无需放开监听地址

### A.1 自动发现模式

步骤 1：放开组件监听地址。修改后 kubelet 会自动重建 Static Pod。

```bash
# controller-manager 与 scheduler
sudo sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/g' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml \
  /etc/kubernetes/manifests/kube-scheduler.yaml

# etcd metrics
sudo sed -i 's#--listen-metrics-urls=http://127.0.0.1:2381#--listen-metrics-urls=http://0.0.0.0:2381#' \
  /etc/kubernetes/manifests/etcd.yaml

sudo ss -tlnp | grep -E '10257|10259|2381'
```

步骤 2：启用采集。

```bash
helm upgrade categraf ./categraf -n flashcat -f my-values.yaml --set controlPlane.enabled=true
```

> **说明**：0.2.2 起 upgrade 会自动滚动 KSM Agent；从 0.2.1 升级且 values 未变更时，需补充执行 kubectl rollout restart statefulset categraf-ksm -n flashcat。

> **注意**：KSM Agent 的 ServiceAccount 需具备 /metrics 非资源权限，Chart 默认已包含 nonResourceURLs 配置；节点防火墙需放通 10257、10259、2381 端口，来源按节点网段放通（Flannel 下 Pod 访问其它节点主机 IP 时源地址会变成节点 IP，只放行 Pod 网段可能不生效）。

步骤 3：验证。在 Master 节点执行：

```bash
# apiserver
kubectl get --raw /metrics | head -20

# controller-manager 与 scheduler
TOKEN=$(kubectl -n flashcat create token categraf)
curl -sk -H "Authorization: Bearer $TOKEN" https://127.0.0.1:10257/metrics | head -20
curl -sk -H "Authorization: Bearer $TOKEN" https://127.0.0.1:10259/metrics | head -20

# etcd
curl -s http://127.0.0.1:2381/metrics | head -20
```

> **说明**：kubectl create token 需 Kubernetes 1.24 及以上版本；etcd metrics 通过 HTTP 暴露，无需认证。

常用指标：

```text
apiserver_request_total
apiserver_request_duration_seconds
workqueue_queue_duration_seconds
scheduler_schedule_attempts_total
etcd_server_has_leader
```

### A.2 远程下发模式

1. 登录 Flashcat 控制台，进入 数据集成 - 数据采集。
2. 新建 Prometheus 采集任务，远程下发至 Master 节点的 Node Agent。
3. 使用 [control-plane.toml](../../assets/examples/control-plane.toml) 模板，按集群修改 labels 中的 cluster 值。

> **说明**：Node Agent 使用 hostNetwork，可直接访问本机 127.0.0.1 的组件端口，无需放开监听地址；验证方式与 A.1 一致。

## 附录 B 完整 values.yaml

完整参数参考（含全部可配置项与注释）见 [values.all.yaml](../../assets/categraf-helm/categraf/values-examples/values.all.yaml)。飞书文档中该文件以附件形式提供。建议只复制需要的片段，不要整体作为 my-values.yaml：整体复制会把当前默认值全部固定，后续 Chart 升级的新默认值不会生效。
