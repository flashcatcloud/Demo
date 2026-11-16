# K8s 接入 Categraf 页面设计

> 适用 Chart `categraf-0.2.3`｜appVersion `0.5.45`｜2026-11-16
> 事实来源：`categraf-0.2.3.tgz` 的 `values.yaml` / `templates`、`docs/01-k8s-base/K8S指标监控.md`、`categraf-operator/README.md`、`docs/附录/发布Chart到仓库.md`
> 本文出现的三段 values（DS 单模式 / STS 单模式 / 组合态）已用 `helm template categraf-0.2.3` 实测渲染通过；资源名取自渲染结果，非推测。

---

## 0. 这份文档解决什么

页面定位：**一个可复制的接入向导**，不是一篇文档。用户进来只做三件事——填几个变量、复制命令、看到"装好了"的确定性信号。

本文档给出的是**页面内容设计**（每节写什么、文案怎么写、命令用哪条、变量插在哪、验证怎么做），不是视觉稿。参考页 `preview--fc-firemap.lovable.app` 为私有预览（HTTP 401），未取到其视觉细节；本文档严格按其 8 节骨架落地，并补齐它在 DS/STS 两个场景下必然缺的部分。

---

## 1. 三个关键决策（先定这三条，后面所有内容都依赖它）

### 1.1 DaemonSet 与 StatefulSet 不是二选一，是同一个 Release 的两个开关

`categraf` chart 一次安装会渲染出 4 个工作负载，各自独立开关：

| 工作负载 | kind | values 开关 | 采什么 |
|---|---|---|---|
| Node Agent | **DaemonSet** | `nodeCategraf.enabled` | 主机指标、kubelet/cAdvisor、kube-proxy、服务拓扑、命令通道 |
| KSM Agent | **StatefulSet** | `ksmCategraf.enabled` | KSM 指标、应用指标（注解发现 + 自定义 job）、CoreDNS/Calico/Cilium |
| kube-state-metrics | Deployment | `kubeStateMetrics.enabled` | 暴露 K8s 对象状态指标（KSM Agent 的抓取目标） |
| Operator | Deployment | `operator.enabled` | 节点删除后清理 Flashcat 残留设备 |

**页面结论**：模式选择做成三选一，而不是两个互斥 Tab。

```
[ 节点采集 DaemonSet ]   [ 集群与应用采集 StatefulSet ]   [ 两者都要（推荐） ]
```

选单模式时，页面自动把另一模式的开关设为 `false`，并**显式渲染出来**（见 4.5 / 5.5 的 values 片段），避免用户以为装了 STS 就有 kubelet 指标。默认选中「两者都要」。

### 1.2 Deployment 模式统一改为 StatefulSet

原方案里的 "Deployment 模式" 全部改成 **StatefulSet（`categraf-ksm`）**，页面不出现 Deployment 这个词（KSM 自身的 Deployment 除外，那是依赖不是本体）。理由：

1. **与 chart 实现一致**：`ksmCategraf` 渲染的就是 StatefulSet（`spec.serviceName: <release>-ksm`），文档写 Deployment 会与 `helm get manifest` 对不上。
2. **ident 稳定**：Pod 名固定为 `<release>-ksm-0`，categraf 的 `hostname = "${CLUSTER_NAME}-${HOSTNAME}"` 因此恒定，设备不会因重启改名而产生重复设备。
3. **唯一出口**：应用发现必须只有一个实例在抓，否则 N 个副本会把同一批 target 抓 N 份。StatefulSet 的稳定序号为将来做分片（`-0/-1` 各抓一半）留了位置，Deployment 的随机后缀做不到。
4. **可回滚**：滚动升级时状态（WAL 除外）与顺序可控，运维心智负担低。

代价：当前 `replicas > 1` 仍会重复抓取（见 5.8 与第 8 章待确认项），页面默认锁定 `replicas: 1` 并给出提示。

### 1.3 Helm 的 `latest`：仓库侧保留，页面命令一律写死版本

结论见第 7 章（含完整论证）。一句话：**`latest` 只做"便捷别名"，不做"版本真相"**；页面所有命令必须带 `--version {{chartVersion}}`，`latest` 只出现在版本徽标的悬浮说明和"获取最新版本"入口。

---

## 2. 页面信息架构

### 2.1 布局

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ 接入 Kubernetes                                    Chart 0.2.3 · Categraf 0.5.45│
│ [节点采集 DaemonSet] [集群与应用 StatefulSet] [两者都要（推荐）]                │
├──────────────────┬─────────────────────────────────────────────────────────────┤
│ 左侧：变量面板    │ 右侧：8 节内容流（每节可折叠、可复制）                       │
│ （吸顶，280px）   │                                                             │
│ ● 服务端地址      │ 1 相关依赖                                                  │
│ ● 集群名          │ 2 运行环境要求                                              │
│ ● 命名空间        │ 3 功能说明                                                  │
│ ● Release 名      │ 4 配置文件        ←── 变量在这里被"消费"                     │
│ ● 环境 / 业务组   │ 5 部署并检查      ←── 命令在这里被"渲染"                     │
│ ● 版本            │ 6 升级                                                      │
│ ● 离线镜像前缀    │ 7 卸载                                                      │
│ ● API Token       │ 8 其他说明                                                  │
│ ▸ 高级参数        │                                                             │
├──────────────────┴─────────────────────────────────────────────────────────────┤
│ 底栏：接入进度 3/8 · [我已完成部署，去验证]                                     │
└────────────────────────────────────────────────────────────────────────────────┘
```

左栏变量的改动**只改渲染结果，不改页面结构**：`4 配置文件` 的 values 片段实时重绘，`5 部署并检查` 的命令行参数实时重绘，已复制的文本不受影响（复制时快照）。

### 2.2 每节统一模板（保证 8 节读起来是同一个东西）

每节固定四块，顺序不变：

1. **一句话目的**（≤25 字，回答"这节为什么存在"）
2. **主体**（表格 / 命令块 / values 片段）
3. **验收信号**（"你看到 X 就说明这步成了"，必须是可观察的事实）
4. **`遇到问题？`** 折叠区（最多 3 条高频失败 + 排查命令）

平台注册/控制台的开关（命令通道、服务拓扑）不进这 8 节正文，只做**行内标注**（`需在控制台开启 →`），避免文档页和产品页抢职责。

### 2.3 交互与埋点

| 元素 | 行为 | 埋点 |
|---|---|---|
| 每个命令块右上角 `复制` | 复制已渲染后的文本（无 `{{}}` 占位） | `onboarding.k8s.copy` + `section` + `mode` + `chartVersion` |
| `版本徽标` | 悬浮显示版本列表 + `latest` 当前指向 + 变更摘要链接 | `onboarding.k8s.version_hover` |
| 左栏变量 | 失焦校验（地址可解析、集群名非空且不含空格、Release 名符合 DNS-1123） | `onboarding.k8s.var_change` + `var` |
| `我已完成` | 打勾并记录时间；8/8 时弹出"下一步：配置告警 / 开启服务拓扑" | `onboarding.k8s.section_done` |
| 失败排查展开 | 无 | `onboarding.k8s.troubleshoot_open` |

---

## 3. 左侧变量面板与注入矩阵

### 3.1 变量清单

| # | 变量 | 控件 | 默认值 | 必填 | 落点（values 键） |
|---|---|---|---|---|---|
| 1 | `FLASHCAT_ADDR` 服务端地址 | 输入框，预填当前站点地址 | 当前站点 | 是 | `categraf.serverAddr` |
| 2 | `CLUSTER_NAME` 集群名 | 输入框 + 唯一性检查 | 当前集群名 | 是 | `categraf.clusterName` |
| 3 | `NAMESPACE` 命名空间 | 输入框 | `flashcat` | 是 | helm `-n` |
| 4 | `RELEASE_NAME` Release 名 | 输入框 | `categraf` | 是 | helm 位置参数 |
| 5 | `ENV` 环境 | 下拉 prod/test/dev | `prod` | 否 | `categraf.env` |
| 6 | `GID` 业务组 | 下拉业务组（可空） | 空 | 否 | `categraf.heartbeatGid` |
| 7 | `CHART_VERSION` 版本 | 下拉（仅 GA） | `0.2.3` | 是 | helm `--version` |
| 8 | `REGISTRY_PREFIX` 镜像前缀 | 输入框（离线场景改） | `registry.flashcat.cloud/public` | 是 | `*.image` 四处置换 |
| 9 | `USER_TOKEN` API Token | 密码框 | 空 | 否（开 operator 则必填） | `operator.userToken` |
| 10 | `INTERVAL` 采集间隔 | 数字 | `15` | 否 | `categraf.config.interval` |
| 11 | `CUSTOM_LABELS` 自定义标签 | key/value 编辑器 | 空 | 否 | `categraf.customLabels` |
| 12 | `RW_USER/RW_PWD` 远程写认证 | 输入框 | `user001` / 空 | 否 | `categraf.remoteWriteUser/Password` |

**页面校验规则（写进 design，别留给前端即兴发挥）**：

- `CLUSTER_NAME`：同一 Flashcat 下必须唯一。左栏实时调一次 `GET /api/n9e/...` 查重，重名时红字提示"该集群名已存在，多 Release 并存时每个 Release 必须使用不同值"。
- `CLUSTER_NAME` 用默认值 `Kubernetes-cluster` 且 `operator.enabled=true` 时，operator 会在启动日志告警（多集群共享时易误删设备）——页面升级为黄条提示。
- `USER_TOKEN` 只在开启 Operator 时展示；关闭 Operator 时该字段隐藏，避免用户误以为 Token 是采集必需。

### 3.2 注入矩阵：变量到底进了哪里

这张表是页面「4 配置文件」一节的骨架，也是客服答疑的第一张表。

| 变量 | 注入位置 | 载体 | 改动后如何生效 |
|---|---|---|---|
| `FLASHCAT_ADDR` | `config.toml` 的 `[global.n9e_server].address` + `[heartbeat].url` + `cluster-scrape.yaml` 的 `remote_write.url` | ConfigMap | `helm upgrade` → 重建 ConfigMap → `checksum/config` 变化 → **滚动重启** |
| `CLUSTER_NAME` | `config.toml` 的 `[global.labels].cluster`、KSM Agent 的 `hostname` 模板、`cluster-scrape.yaml` 的 `external_labels.cluster`、容器 env `CLUSTER_NAME` | ConfigMap + env | 同上 |
| `ENV` | `[global.labels].env` | ConfigMap | 同上 |
| `GID` | 不进模板，走**心跳**归组（`heartbeatGid` 透传到心跳请求） | 心跳 | 改 values 后滚动重启即归组；控制台也可手动移组 |
| `INTERVAL` | `[global].interval` + 各 `input` 的 `interval` + `scrape_interval` | ConfigMap | 同上 |
| `CUSTOM_LABELS` | 两类 Agent 的 `[global.labels]` 与 `cluster-scrape.yaml` 的 `external_labels` | ConfigMap | 同上（`env`/`cluster`/`categraf` 为保留键，覆盖会被 chart 拒绝） |
| `REGISTRY_PREFIX` | `nodeCategraf.image`、`ksmCategraf.image`、`kubeStateMetrics.image`、`operator.image` | Pod spec | 改后 `helm upgrade` 触发拉新镜像重启 |
| `USER_TOKEN` | Operator 的 Secret/env | Secret | 只有 Operator 重启，不影响采集 |
| K8s API 权限 | ServiceAccount + ClusterRole（`rbac.yaml`，不由用户填） | RBAC | 装/卸时变更 |

### 3.3 启动参数：页面**不能**替换，也不该提供输入框

两个容器的启动参数在模板里是硬编码的：

```yaml
command: ["/usr/bin/categraf"]
args: ["-configs", "/opt/categraf/conf"]
```

这意味着：

- 页面**不要**设计"启动参数"输入框，它会误导用户以为能加 `--debug` 之类。真实可变面只有 `values → ConfigMap → 挂载路径`。
- 唯一与"启动参数"沾边、且可被业务感知的是 **`CATEGRAF_HOST_EXEC_PROFILE` 环境变量**（Node Agent 专用，由 `nodeCategraf.hostExec.enabled` 推导：`true` 时强制 `privileged: true` 并挂载 `/var/lib/categraf/ibex`）。页面表达为**开关**（"命令通道能力"），不暴露成 env 输入框。
- config 文件是**单文件挂载**（`subPath`），不是目录级覆盖：`config.toml`、`/etc/categraf/cluster-scrape.yaml`、`input.prometheus/cadvisor.toml`、`input.node_exporter/`、`input.<plugin>/<plugin>.toml` 各自 subPath。这决定了"用户想自己塞一个 input 文件"在当前 chart 下做不到——页面要在 `8 其他说明` 里说清，并指向 `appMetrics.extraScrapeConfigs` 与远程下发两条替代路径。

### 3.4 运行时可变 vs 必须重装（很重要，客服最常被问）

| 想改的东西 | Node Agent（DS） | KSM Agent（STS） |
|---|---|---|
| 采集间隔、服务端地址、标签 | `helm upgrade`（滚动重启，秒级中断） | `helm upgrade`（同左） |
| 采集任务（控制台创建/远程下发） | ✅ 免重启：`providers = ["local","http","rmq"]` | ❌ 仅 `["local"]`，只认 `cluster-scrape.yaml` |
| 抓取哪些应用/组件 | — | 只能改 values 后 `helm upgrade`；或控制台下发的"应用发现"（需确认是否已支持） |
| 镜像 | `helm upgrade` | `helm upgrade` |

> 页面文案（放在 3.4 对应折叠区）：**Node Agent 支持控制台远程下发采集任务，改完无需重启；KSM Agent 的抓取目标来自集群内配置文件，任何调整都要走一次 `helm upgrade`。** 这条差异必须在两个模式的「4 配置文件」里都出现，否则用户会在 STS 上找"下发按钮"。

---

## 4. DaemonSet 模式 · 8 节内容

### 4.1 相关依赖

> 【页面目的】安装前把"要准备什么"一次讲完，避免装到一半卡在镜像。

**主体**：依赖清单表 + 一句"依赖已随离线包打包"。

| 依赖 | 版本 | 形态 | 页面给什么 |
|---|---|---|---|
| `categraf` Helm Chart | `0.2.3` | OCI `oci://registry.flashcat.cloud/public/charts/categraf` | 复制命令 + 离线 `.tgz` 下载 |
| Node Agent 镜像 | `categraf_ent:servicemap-v0.5.45` | 容器镜像 | 内网仓库前缀替换 |
| KSM Agent 镜像 | `categraf_ent:v0.5.45` | 容器镜像 | 仅"两者都要"时出现 |
| kube-state-metrics | `kube-state-metrics:v2.19.1` | 容器镜像 | 仅"两者都要"时出现 |
| categraf-operator | `categraf-operator:0.0.7` | 容器镜像 | 仅开启 Operator 时出现 |
| Helm | ≥ 3（4.2.3 已验模板渲染） | 客户端 | 环境要求一节引用 |
| 采集 SDK / 语言 Agent / 编译库 | **无** | — | 明确写"本模式不需要任何 SDK" |
| 宿主机能力 | `hostNetwork` / `hostPID` / `privileged` / hostPath `/`（只读） | 节点级 | 环境要求一节引用 |

> 【页面文案】
> **依赖说明**：所需 Chart 与镜像已随 Flashcat 离线包（`flashcat-offline-bundle`）一并打包，可在内网直接导入，无需访问公网。历史版本请到 [官网下载页](https://flashcat.cloud/download) 获取；页面默认给出当前稳定版 `0.2.3`。

**关于 latest（页面必须写清的一行）**：

> 【页面文案】页面展示的版本号是**具体版本**（如 `0.2.3`）；镜像与 Chart 若使用 `latest` 标签，启动后请以实际版本为准：Chart 看 `helm list`/`helm show chart`，Categraf 看 `categraf --version` 或设备详情。

**验收信号**：不适用（本节是清单，不打勾）。但提供 `一键检测` 按钮：在用户粘贴集群 kubeconfig 的场景不可行，改为给命令 `kubectl version --short && helm version --short`，让用户自证。

**遇到问题？**
- 拉不到 `registry.flashcat.cloud` → 走 `.tgz` 离线安装分支（页面给第二条命令）。
- `operator.userToken` 为空但 `operator.enabled=true` → chart 直接报错，页面在 values 片段里用注释标必填。

### 4.2 运行环境要求

> 【页面目的】把硬门槛摆在命令之前，避免装完才发现 Pod 起不来。

**主体**：表格 + 强制提示条。

| 项 | 要求 | 不满足的后果 |
|---|---|---|
| Kubernetes | `>= 1.19`，`< 1.38`（1.28.2 实机验证；1.32+ 仅模板渲染验证） | Helm 直接拒绝安装（`kubeVersion` 校验） |
| Helm | ≥ 3.x | 无法安装 |
| 节点 OS | Linux（cgroup v1/v2 均可） | 不支持 Windows 节点，DS 会在 Windows 节点失败 |
| Pod Security | 命名空间不能是 `baseline`/`restricted`（两者都禁 host namespaces）；建议 `pod-security.kubernetes.io/enforce=privileged` | `hostNetwork`/`hostPID`/`privileged` 被 PSA 拒绝，Pod 起不来 |
| 节点 taint | Chart 默认 `tolerations: [{effect: NoSchedule, operator: Exists}]`，只容忍 `NoSchedule` | 带 `NoExecute` taint 的节点不会调度 DS Pod |
| 出向网络 | 节点 → `FLASHCAT_ADDR`（HTTP 19000） | 指标写不进、设备一直离线 |
| 入向端口 | **无需开放**（categraf 是 push 模式） | — |
| 内核 | 老内核上部分 node_exporter collector 会报错并跳过（如 `pressure` 需内核 4.20+） | 指标缺失，不影响启动 |
| 单节点资源 | requests `200m / 512Mi`，limits `2000m / 2Gi` | 节点资源紧张时被驱逐 |

> 【页面文案】**环境要求**：Kubernetes 1.19～1.37，Helm 3+，Linux 节点，命名空间需允许 `privileged` + `hostNetwork` + `hostPID`。
> ⚠️ **不满足此环境要求，请联系 Flashcat 技术人员提供支持。**

**为什么必须是 privileged**（做成一行说明，不要展开成段）：

> `privileged: true` 是默认值：既能采指标/读宿主文件，也能以宿主机视角执行诊断命令（命令通道全能力）。设为 `false` 时仍可采集，但**服务拓扑会自动降级为轮询模式（无 L7 解析）**，命令通道不可用。

**验收信号**：`kubectl version --short` 与 `helm version --short` 输出满足上表。

**遇到问题？**
- `pods "categraf-xxx" is forbidden: violates PodSecurity "restricted"` → 给命名空间打 PSA 标签的命令。
- `did not tolerate taint` → `kubectl describe node <node> | grep -i taint`，页面给出往 `nodeCategraf.tolerations` 追加的片段。

### 4.3 功能说明

> 【页面目的】让用户知道"装完能拿到什么"，尤其是需要额外开启的两项。

**主体**：能力表（能力 / 采什么 / 关键指标 / values 开关 / 是否需要页面开启）。

| 能力 | 采集内容 | 关键指标 | values 开关 | 额外条件 |
|---|---|---|---|---|
| **Node 指标**（默认 `node_exporter` 插件） | CPU/内存/磁盘/文件系统/网卡/负载/内核等，`--path.rootfs=/hostfs` 采集宿主 | `node_load1`、`node_filesystem_avail_bytes`、`node_network_receive_bytes_total` | `nodeCategraf.inputs.nodeExporter` | 默认开 |
| **原生主机指标**（Nightingale 风格） | `cpu/mem/disk/diskio/net/netstat/system/kernel/swap/process` | `cpu_usage_idle`、`mem_used_percent` | `nodeCategraf.inputs.hostNative.*` | 默认全开；Flashcat 主机大盘默认匹配这套 |
| **kubelet / cAdvisor** | 容器 CPU/内存/网络/文件系统 + kubelet 自身 | `container_cpu_usage_seconds_total`、`kubelet_running_pods` | `nodeCategraf.inputs.cadvisor` | 默认开 |
| **kube-proxy** | iptables/ipvs 模式与规则数 | `kubeproxy_sync_proxy_rules_duration_seconds` | `kubeProxy.enabled` | 默认开；依赖 `hostNetwork` 访问 `127.0.0.1:10249` |
| **任务通道（命令通道）** | 控制台向节点下发脚本，宿主机视角执行 | — | `nodeCategraf.hostExec.enabled` | 默认开；**需在控制台「任务通道」开启** |
| **服务拓扑（Service Map）** | 基于 eBPF/L7 解析出服务间调用关系 | — | 镜像 variant + `hostname: nodeName` | **需在控制台「服务拓扑」开启**；ident 必须是节点名 |
| **自定义标签** | `region`、`owner` 等附加到全部上报 | — | `categraf.customLabels` | `env/cluster/categraf` 为保留键 |
| **多集群隔离** | 同一 Flashcat 下的集群区分 | — | `categraf.clusterName` | 必须全局唯一 |

> 【页面文案】
> 下述安装命令，会在 Kubernetes 集群的**每个 Node 节点**部署一个 Categraf（DaemonSet），并提供以下能力：
> - **Node 指标采集**（默认 `node_exporter` 插件，同时保留原生主机插件以匹配 Flashcat 主机大盘）
> - **kubelet / cAdvisor 容器指标采集**
> - **kube-proxy 指标采集**
> - **任务通道**（控制台下发脚本到宿主机执行，需在控制台「任务通道」开启）
> - **服务拓扑信息抓取**（需在控制台「服务拓扑」开启）
> - **自定义标签与多集群隔离**

**验收信号**：本节不打勾，但表格里两个"需在控制台开启"用 `→` 跳转按钮，点击后新开标签页。

**遇到问题？**
- 只要 node_exporter 语义、不要双份主机指标 → 给 `hostNative.enabled: false` 片段（会导致 Flashcat 主机大盘部分面板空，需提示）。
- 服务拓扑无数据 → 检查 `nodeCategraf.hostname` 是否为 `nodeName`。

### 4.4 配置文件

> 【页面目的】给出"可粘贴的 values + 渲染后的样子 + 变量在哪"，让用户能自己改而不怕改坏。

**主体**：三段，顺序固定。

**① 页面生成的 `my-values.yaml`（左栏变量已替换）**

```yaml
categraf:
  serverAddr: "http://flashcat.example.com:19000"   # ← FLASHCAT_ADDR
  clusterName: "demo-cluster"                        # ← CLUSTER_NAME，必须全局唯一
  env: "prod"                                        # ← ENV
  heartbeatGid: "2"                                  # ← GID，设备自动归入该业务组（可空）
  config:
    interval: 15                                     # ← INTERVAL
  # customLabels:
  #   region: cn-shanghai

operator:
  enabled: true
  userToken: "<FLASHCAT_USER_TOKEN>"                 # ← USER_TOKEN，必填

nodeCategraf:
  enabled: true
  hostname: nodeName        # ident = 节点名；服务拓扑要求此项不可改
  securityContext:
    privileged: true
  hostExec:
    enabled: true           # 任务通道
  inputs:
    cadvisor: true
    nodeExporter: true
    hostNative:
      enabled: true

# —— 本模式不部署集群级组件（选「两者都要」时由页面自动去掉这一段）——
ksmCategraf:
  enabled: false
kubeStateMetrics:
  enabled: false
appMetrics:
  enabled: false
coreDns:
  enabled: false
networkPlugin:
  calico:
    enabled: false
  cilium:
    enabled: false
```

**② 渲染后的 `config.toml`（只读预览，来自 `helm template`）**

```toml
[global]
print_configs = false
hostname = "${HOSTNAME}"          # env HOSTNAME = spec.nodeName
omit_hostname = false
precision = "ms"
interval = 15
providers = ["local", "http", "rmq"]   # ← 支持控制台远程下发

[global.labels]
env = "prod"
cluster = "demo-cluster"
categraf = "nodeAgent"

[global.n9e_server]
address = "http://flashcat.example.com:19000"

[writer_opt]
batch = 2000
chan_size = 1000000

[heartbeat]
enable = true
url = "http://flashcat.example.com:19000/v1/n9e-plus/heartbeat"
interval = 10
timeout = 5000
dial_timeout = 2500
```

**③ 挂载与变量落点**

| 文件/目录 | 容器路径 | 来源 | 对应变量 |
|---|---|---|---|
| `config.toml` | `/opt/categraf/conf/config.toml`（subPath） | ConfigMap `<release>-config` | 服务端地址/集群名/env/interval |
| node_exporter 插件 | `/opt/categraf/conf/input.node_exporter/` | ConfigMap `<release>-input-node-exporter` | `inputs.nodeExporter` |
| cAdvisor 任务 | `/opt/categraf/conf/input.prometheus/cadvisor.toml` | ConfigMap `<release>-input-cadvisor` | `inputs.cadvisor` |
| kube-proxy 任务 | `/opt/categraf/conf/input.prometheus/kube-proxy.toml` | ConfigMap `<release>-input-kube-proxy` | `kubeProxy.enabled` |
| 原生主机插件 | `/opt/categraf/conf/input.<plugin>/<plugin>.toml` | 各 ConfigMap（关闭时挂空 ConfigMap 覆盖镜像默认） | `inputs.hostNative.*` |
| 命令通道元数据 | `/var/lib/categraf/ibex` | hostPath `/var/lib/categraf/ibex`（DirectoryOrCreate） | `hostExec.enabled` |
| 宿主机根 | `/hostfs`（只读，`mountPropagation: HostToContainer`） | hostPath `/` | 固定 |

> 【页面文案（变量提醒，放在 values 片段上方）】
> **左侧变量会替换这些位置**：`serverAddr`、`clusterName`、`env`、`heartbeatGid`、`interval`、`customLabels`、镜像前缀。
> **不可替换**：容器启动参数固定为 `-configs /opt/categraf/conf`；`config.toml` 为 subPath 单文件挂载，不支持整目录覆盖。

**验收信号**：`helm template` 预览可展开（页面内嵌 `helm template --set ...` 的等价渲染结果，只读）。

**遇到问题？**
- 想加自己写的 input 文件 → 当前 chart 不支持，改走控制台远程下发（DS 支持）或提需求。
- 改 values 后 Pod 没重启 → 0.2.2 起 checksum 基于渲染结果，会自动滚动；0.2.1 及更早需手动 `rollout restart`。

### 4.5 部署并检查

> 【页面目的】一条命令装完，三个信号确认成功。

**主体**：命令 + 验收清单。

```bash
# ① 安装（在线）
helm upgrade --install categraf \
  oci://registry.flashcat.cloud/public/charts/categraf \
  --version 0.2.3 \
  -n flashcat --create-namespace \
  -f my-values.yaml

# ① 安装（离线，已导入 chart tgz 与镜像）
#    本地目录安装时版本取自 Chart.yaml，不需要 --version
helm upgrade --install categraf ./categraf \
  -n flashcat --create-namespace \
  -f my-values.yaml
```

```bash
# ② 检查工作负载
kubectl -n flashcat get ds categraf
kubectl -n flashcat get pods -o wide

# ③ 期望 Pod 数 = 节点数（排除带 NoExecute taint 的节点）
kubectl get nodes --no-headers | wc -l
```

**验收清单**（页面做成 3 个可勾选项）：

| # | 信号 | 怎么确认 | 说明 |
|---|---|---|---|
| 1 | DS 已就绪 | `kubectl -n flashcat get ds categraf` 的 `DESIRED == READY == 节点数` | 不等说明有节点没调度上，看 `describe` |
| 2 | Pod 无报错 | `kubectl -n flashcat logs ds/categraf --tail=50` 无 `error`/`connection refused` | 常见是服务端地址不通 |
| 3 | 设备在线 | Flashcat「设备列表」出现该集群节点设备，`target_up=2` | 2 表示在线，0/1 表示失联 |
| 4 | 指标有数 | 查 `node_load1{cluster="demo-cluster"}` 有数据 | 无数据先看心跳 |
| 5 | 容器指标有数 | 查 `container_cpu_usage_seconds_total{job="kubelet"}` | 空说明 `cadvisor` 被关或 kubelet 10250 不通 |
| 6 | 命令通道可用 | 控制台「任务通道」对该节点执行 `uname -a` | `hostExec.enabled` 必须为 true |

> 【页面文案】装完请确认：**DS 就绪副本数 = 集群节点数**、Pod 日志无报错、Flashcat 设备列表出现该集群节点且在线。三项都对，节点接入就完成了。

**遇到问题？**
- `DESIRED > READY` → 节点 taint / 资源不足 / PSA 拒绝；给 `kubectl -n flashcat describe pod` 指引。
- 设备离线 → 检查 `serverAddr` 是否可从节点访问：`kubectl -n flashcat exec ds/categraf -- curl -sv http://<addr>:19000` （镜像内有 curl 时）。
- 容器指标空 → `curl -k -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://127.0.0.1:10250/metrics/cadvisor` 在节点上验证 10250。

### 4.6 升级

> 【页面目的】告诉用户"升级只是换个版本号"，并暴露唯一那个坑。

**主体**：命令 + 版本对照 + 坑。

```bash
# ① 备份当前 values（升级出问题时可回滚）
helm -n flashcat get values categraf > categraf-values.backup.yaml

# ② 升级到指定版本
helm upgrade categraf \
  oci://registry.flashcat.cloud/public/charts/categraf \
  --version {{新版本}} \
  -n flashcat -f my-values.yaml

# ③ 观察滚动
kubectl -n flashcat rollout status ds/categraf
```

| 操作 | 命令 | 影响 |
|---|---|---|
| 只换 Categraf 镜像版本 | 改 `nodeCategraf.image` 后 `helm upgrade` | DS 全量滚动，秒级采集中断 |
| 换 Chart 版本 | `--version` | 配置模板可能变化，需看变更说明 |
| 回滚 | `helm rollback categraf <REVISION> -n flashcat` | 适用于同集群同 values |

> 【页面文案（升级说明，必须保留）】
> 0.2.2 起 checksum 基于**渲染后的配置**，升级会自动滚动 Pod 加载新配置。
> 从 **0.2.1 或 0.2.2-rc.1** 升级且 values 未变更时，旧版本不会自动刷新配置，需补充执行：
> ```bash
> kubectl rollout restart ds/categraf -n flashcat
> ```

**验收信号**：`kubectl -n flashcat get pods` 全部 `Running` 且 `AGE` 是刚刚；Flashcat 设备 `target_up=2` 未掉。

**遇到问题？**
- 升级后 Pod `CrashLoopBackOff` → `kubectl logs` 看 `config.toml` 解析错误，多半是 `customLabels` 写了保留键或非法标签名（chart 会拒绝）。
- 升级后指标断档 → 检查是否漏了 `rollout restart`。

### 4.7 卸载

> 【页面目的】卸载不只有一条命令，还有"设备会不会被删"这个决策。

**主体**：命令 + 清理行为说明 + 保留设备的两种方式。

```bash
# 默认卸载：会顺带清理本集群在 Flashcat 上的设备（pre-delete hook）
helm uninstall categraf -n flashcat --wait

# 只想删工作负载、保留设备
helm uninstall categraf -n flashcat --no-hooks
# 或卸载前把 cleanup 关掉（需先 upgrade 一次，见下）
```

```yaml
# 保留设备：卸载前先把清理开关关掉，再 upgrade + uninstall
operator:
  cleanup:
    nodeCategraf: false
    ksmCategraf: false
```

> 【页面文案（卸载说明）】
> `operator.cleanup.nodeCategraf` 默认 `true`：卸载会先停止采集、等待设备心跳停止（`CLEANUP_HEARTBEAT_TIMEOUT`，默认 2 分钟）后删除本集群在 Flashcat 上的设备。
> 清理仅作用于本集群，不影响其它集群，**不会删除业务组**。需要保留设备请用 `--no-hooks` 或先把 `cleanup` 设为 `false`。
> `pre-delete` hook 失败会**中止卸载**（资源会留在集群里），确认要强删时用 `--no-hooks`。

**验收信号**：`kubectl -n flashcat get ds` 无结果；`kubectl -n flashcat get pods` 为空；Flashcat 设备列表该集群设备消失（或按预期保留）。

**遇到问题？**
- `helm uninstall` 卡住 → pre-delete hook Job 在等心跳超时，最长 2 分钟；超时仍失败用 `--no-hooks`。
- 卸载后命名空间、ClusterRole 残留 → chart 不删 namespace（正常），ClusterRole 随 release 删除；手动删命名空间命令给出。

### 4.8 其他说明

> 【页面目的】把"刁钻但一定会被问"的场景集中收口，避免散落在各节。

**主体**：抽屉式列表，每条 = 场景 + 结论 + 片段/命令。

| # | 场景 | 做法 | 副作用 |
|---|---|---|---|
| 1 | **不开启 Node 采集**，只用容器指标/命令通道/拓扑 | `nodeCategraf.inputs.nodeExporter: false` + `hostNative.enabled: false` | Flashcat 主机大盘（基于原生主机指标）会空；`node_*` 指标消失 |
| 2 | **只关一部分主机插件** | `hostNative: {cpu: true, mem: true, disk: false, ...}` | 对应面板空 |
| 3 | **开启 kubelet 采集** | `nodeCategraf.inputs.cadvisor: true`（默认已开），采 `/metrics/cadvisor` 与 `/metrics` | 需要 kubelet 10250 可达（`hostNetwork` + SA Token） |
| 4 | **关闭 kubelet 采集** | `cadvisor: false` | 容器指标消失，KSM 仍在 |
| 5 | **自动注册到某个业务组** | `categraf.heartbeatGid: "<GID>"` | 设备心跳自动归组；控制台仍可手动移组 |
| 6 | **缩容/节点删除后自动删设备** | Operator（默认开）：Node 删除事件 → 打 `categraf_node_gone` 标签 → 等观察期（chart 默认 4h）→ 校验心跳停止 + ident 唯一 → 删设备。另有全量 reconcile（5m）与失联节点兜底（7 天） | 观察期内设备仍显示；机器被直接销毁但 Node 对象残留时由 `MAX_NODE_STALE_DURATION` 兜底 |
| 7 | **关闭 Operator** | `operator.enabled: false` | 节点缩容后的残留设备需手工清理 |
| 8 | **多 Release 并存**（如分环境两套） | 每个 Release 用不同 `clusterName` + 不同 `-n`/Release 名 | `clusterName` 重复会导致设备互串、operator 清理误伤 |
| 9 | **不支持 Windows 节点** | — | Windows 节点上 DS Pod 会失败；需要 Windows 容器监控请走容器日志/其他方案 |
| 10 | **想自己控制 tolerations** | `nodeCategraf.tolerations` 覆盖（默认容忍全部 `NoSchedule`） | 覆盖不当会导致部分节点无 DS Pod |

> 【页面文案（Operator 一段，独立成卡片）】
> **节点缩容后设备不残留**：Chart 内置 `categraf-operator`，监听 Node 删除事件，给对应设备打标记、等观察期过后确认心跳已停再删除。节点被直接销毁（Node 对象残留）时，由"失联节点检测"兜底（默认 7 天）。业务组不会被自动删除。

> 【页面文案（一处必须写的边界）】
> Operator 的自动清理**只覆盖 Node Agent（DaemonSet）**：它监听的是 K8s Node 删除，不是 Pod 缩容。KSM Agent（StatefulSet）的设备清理只发生在 `helm uninstall`。若你需要"减少 STS 副本时自动删设备"，请联系 Flashcat 技术人员。

---

## 5. StatefulSet 模式 · 8 节内容

### 5.0 先回答：为什么是 StatefulSet，以及两个场景怎么在一个 STS 里完成

页面在这一节之前放一个**能力边界表**，让用户明确"STS 不替代 DS"：

| 数据类型 | DaemonSet | StatefulSet |
|---|---|---|
| 主机指标（node_exporter / 原生插件） | ✅ | ❌ |
| kubelet / cAdvisor | ✅ | ❌ |
| kube-proxy（仅 127.0.0.1:10249） | ✅（依赖 hostNetwork） | ❌ |
| KSM（K8s 对象状态） | ❌ | ✅ |
| 应用指标（注解发现 / 自定义 job） | ❌（每节点重复抓，禁止） | ✅ 唯一出口 |
| CoreDNS / Calico / Cilium | ❌ | ✅ |
| 控制平面 | ✅（远程下发） | ✅（K8s SD 自动发现，需放开监听地址） |
| 服务拓扑 / 命令通道 | ✅ | ❌ |

**两个场景，一个 StatefulSet**：

`categraf-ksm` 只挂一个抓取配置文件 `/etc/categraf/cluster-scrape.yaml`，其中 `scrape_configs` 是数组。两个场景就是数组里的两个 job，互不冲突：

| | 场景 A：规范型（按约定抓） | 场景 B：非规范型（点对点抓） |
|---|---|---|
| 触发 | `appMetrics.defaultJob.enabled: true` | `appMetrics.extraScrapeConfigs: [...]` |
| 业务侧要做什么 | 打 `prometheus.io/scrape` / `port` / `path` / `scheme` 注解 + `app`、`team` 标签 | **什么都不用做**（不改 Pod、不重启） |
| job_name | `app-metrics`（内置） | 自定义（如 `redis-exporter`） |
| 发现方式 | Pod SD + `prometheus.io/scrape=true` 过滤 | Pod/Endpoints SD + 按 namespace/service/label 过滤 |
| 维护成本 | 0（新增服务自动纳管） | 每接一个中间件加一段配置 |
| 适用 | 自研服务、能改 Deployment 的应用 | 中间件、第三方组件、不能重启的存量服务 |

**合并原则（页面要显式写出来）**：

1. 两个 job 并存于同一份 `scrape_configs`，**A 不会拦截 B，B 不会影响 A**。
2. 二者都抓同一个 target 时会产生重复（同一 `__address__` 不同 `job` 标签 → 两组时间线）。页面提示："同一个 target 只走一条路径"。
3. 想彻底只按清单抓：`appMetrics.defaultJob.enabled: false`（0.2.2 起），此时 A 完全关闭，只剩 B。
4. 新增一个"符合规范"的服务 = 业务侧加注解，**不需要重新 `helm upgrade`**；新增一个"不符合规范"的中间件 = 改 values 后 `helm upgrade`（STS 滚动，秒级）。

### 5.1 相关依赖

> 【页面目的】同 4.1，但依赖集不同：STS 不需要宿主机特权，却需要 KSM 与集群级 RBAC。

**主体**：

| 依赖 | 版本 | 形态 | 说明 |
|---|---|---|---|
| `categraf` Helm Chart | `0.2.3` | OCI / `.tgz` | 同 4.1 |
| KSM Agent 镜像 | `categraf_ent:v0.5.45` | 容器镜像 | 与 DS 镜像**不同**（DS 用 `servicemap-v0.5.45`），页面必须分别展示 |
| kube-state-metrics | `kube-state-metrics:v2.19.1` | 容器镜像 | `kubeStateMetrics.enabled: true` 时部署 |
| categraf-operator | `categraf-operator:0.0.7` | 容器镜像 | 仅卸载清理用，可选 |
| 集群级 RBAC | ClusterRole/ClusterRoleBinding | 清单内置 | list/watch `pods`、`services`、`endpoints`、`nodes` |
| 采集 SDK | **无** | — | 本模式不需要 SDK；应用侧只需能暴露 `/metrics` |

> 【页面文案】本模式**不占用宿主机特权**、不需要 `hostNetwork`/`hostPID`，权限只到 K8s API 只读。

**验收信号**：不适用。

**遇到问题？**
- 集群禁用 ClusterRole 创建（受限租户）→ 无法做 pod/endpoint 发现，只能改用 DS 远程下发或侧车方案，页面给"联系技术支持"。

### 5.2 运行环境要求

| 项 | 要求 | 不满足的后果 |
|---|---|---|
| Kubernetes | `>= 1.19`，`< 1.38` | Helm 拒绝安装 |
| Helm | ≥ 3.x | — |
| K8s API | 允许 ClusterRole/ClusterRoleBinding | 无法发现 target |
| KSM | `kubeStateMetrics.enabled: true`（默认）或集群已有 KSM | 无 `kube_*` 指标 |
| 网络 | STS Pod → 各业务 Pod 的指标端口；→ `FLASHCAT_ADDR` | `up=0` |
| NetworkPolicy | 放通 `flashcat` 命名空间到业务命名空间的指标端口 | 连接被拒 |
| 抓取间隔 | 默认 `15s`，与应用侧 `/metrics` 性能匹配 | 应用指标端点被打挂 |
| 资源 | requests `500m / 512Mi`，limits `1000m / 1.5Gi` | OOM/限流 |
| 副本 | **固定 `replicas: 1`**（多副本重复抓取） | 指标重复、写入放大 |

> 【页面文案】**环境要求**：Kubernetes 1.19～1.37，Helm 3+，具备集群级只读 RBAC，`flashcat` 命名空间到业务 Pod 指标端口的网络可达。
> ⚠️ **不满足此环境要求，请联系 Flashcat 技术人员提供支持。**

**验收信号**：`kubectl auth can-i list pods --all-namespaces --as=system:serviceaccount:<NS>:<RELEASE>` 返回 `yes`。

### 5.3 功能说明

> 【页面目的】把"一个 STS 能干什么"讲清，尤其是两个采集场景。

**主体**：能力表 + 两场景对照入口。

| 能力 | 采集内容 | 关键指标 | values 开关 |
|---|---|---|---|
| **KSM 指标** | Pod/Deployment/StatefulSet/Service/Node/PVC 等对象状态 | `kube_pod_status_phase`、`kube_deployment_status_replicas_ready` | `ksmCategraf.jobs.kubeStateMetrics` |
| **应用指标 · 规范发现（场景 A）** | 带 `prometheus.io/*` 注解的 Pod | `up{job="app-metrics"}` + 业务指标 | `appMetrics.defaultJob.enabled` |
| **应用指标 · 自定义 job（场景 B）** | 指定 namespace/service/label 的 target | `up{job="<自定义>"}` | `appMetrics.extraScrapeConfigs` |
| **CoreDNS** | DNS 请求量/延迟/缓存 | `coredns_dns_request_duration_seconds` | `coreDns.enabled` |
| **Calico / Cilium** | 网络插件健康与转发 | `cilium_endpoint_state`、`felix_*` | `networkPlugin.*` |
| **控制平面（可选）** | apiserver/scheduler/controller-manager/etcd | `apiserver_request_total` | `controlPlane.enabled`（需放开监听地址） |
| **远程写** | 走 Prometheus remote_write 写入 Flashcat | — | `categraf.remoteWriteUser/Password` |

> 【页面文案】
> 下述安装命令，会以 **StatefulSet** 的方式部署一个集群级 Categraf（`<release>-ksm`，默认 1 副本），并提供：
> - **KSM 指标采集**（K8s 对象状态）
> - **应用指标自动发现**：符合 `prometheus.io/*` 规范的服务自动纳管，无需逐个配置
> - **自定义采集任务**：不符合规范、不能改注解的中间件，用原生 `scrape_configs` 逐条配置
> - **K8s 组件采集**：CoreDNS、Calico/Cilium、控制平面（可选）
> - **统一出口**：所有应用/集群指标从这里写入 Flashcat，不重复、不错位

**验收信号**：本节不打勾；两场景卡片各带"我要用这个"按钮，点击跳到 5.4 对应片段。

**遇到问题？**
- 以为 STS 能采 kubelet → 能力边界表里已标 ❌，页面加"kubelet 请用 DaemonSet 模式"的链接。
- `up{job="app-metrics"}` 为空 → 见 5.5 排查。

### 5.4 配置文件

> 【页面目的】一个 values 同时表达两个场景；让用户看清"规范"和"清单"各自长什么样。

**主体**：values + 渲染后的 scrape 配置 + 两个场景的示例。

**① `my-values.yaml`**

```yaml
categraf:
  serverAddr: "http://flashcat.example.com:19000"   # ← FLASHCAT_ADDR
  clusterName: "demo-cluster"                        # ← CLUSTER_NAME
  env: "prod"                                        # ← ENV
  # remoteWriteUser: "user001"                      # 需要 remote_write 认证时填
  # remoteWritePassword: ""

operator:
  enabled: true
  userToken: "<FLASHCAT_USER_TOKEN>"

ksmCategraf:
  enabled: true
  replicas: 1                     # 固定 1，多副本会重复抓取
  jobs:
    kubeStateMetrics: true

kubeStateMetrics:
  enabled: true                   # 未自建 KSM 时保持开启

appMetrics:
  enabled: true
  defaultJob:
    enabled: true                 # 场景 A：规范注解自动发现
  extraScrapeConfigs: []          # 场景 B：不合规范时在这里逐条加

# —— 本模式不部署节点级组件（选「两者都要」时由页面自动去掉这一段）——
nodeCategraf:
  enabled: false
kubeProxy:
  enabled: false                  # kube-proxy 只能由 Node Agent 采

coreDns:
  enabled: true
networkPlugin:
  calico:
    enabled: true
  cilium:
    enabled: false                 # 按集群实际插件只留一个
controlPlane:
  enabled: false
```

**② 场景 A：业务侧要打的注解（给研发看的那段）**

```yaml
# 业务 Deployment 的 spec.template.metadata
metadata:
  labels:
    app: order-service        # → 指标标签 service
    team: platform            # → 指标标签 team
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"          # 容器端口，不是 Service 端口
    prometheus.io/path: "/metrics"      # Spring Boot 用 /actuator/prometheus
    prometheus.io/scheme: "http"
```

抓取后自动附带：`namespace`、`pod`、`service`、`team`，以及集群级 `cluster`、`env`、`customLabels`。

**③ 场景 B：不能改注解时的追加配置（页面给两个可直接粘的样例）**

```yaml
appMetrics:
  extraScrapeConfigs:
    # 中间件 1：Redis Exporter（Service/Endpoints）
    - job_name: redis-exporter
      kubernetes_sd_configs:
        - role: endpoints
      relabel_configs:
        - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name]
          action: keep
          regex: middle;redis-exporter
        - source_labels: [__meta_kubernetes_endpoint_address_target_name]
          target_label: instance

    # 中间件 2：MySQL Exporter（按 Pod 标签，端口写死）
    - job_name: mysql-exporter
      metrics_path: /metrics
      kubernetes_sd_configs:
        - role: pod
          namespaces:
            names: [middle]
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          action: keep
          regex: mysql-exporter
        - source_labels: [__meta_kubernetes_pod_ip]
          target_label: __address__
          replacement: ${1}:9104
        - source_labels: [__meta_kubernetes_pod_label_app]
          target_label: service
        - source_labels: [__meta_kubernetes_pod_name]
          target_label: pod
```

> 【页面文案（场景 B 必读）】
> 每个列表项必须是**完整、合法的 Prometheus `scrape_config`**，Chart 只做追加，不改写、不去重。
> 只想按清单抓、彻底关掉规范发现：设置 `appMetrics.defaultJob.enabled: false`（0.2.2 起）。

**④ 渲染后的 `/etc/categraf/cluster-scrape.yaml`（只读预览，节选）**

```yaml
global:
  scrape_interval: 15s
  external_labels:
    cluster: "demo-cluster"

scrape_configs:
  - job_name: 'kube-state-metrics'
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: flashcat;categraf-kube-state-metrics;http-metrics

  - job_name: 'app-metrics'          # ← 场景 A
    metrics_path: /metrics
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      # ... service/team/port/path/scheme 规则
  # ← 场景 B 的自定义 job 追加在这之后

  - job_name: 'coredns'
    # ...
  - job_name: 'calico'
    # ...
  - job_name: 'cilium'
    # ...

remote_write:
  - url: 'http://flashcat.example.com:19000/prometheus/v1/write'
    basic_auth:
      username: "user001"
      password: ""
```

**⑤ 挂载与变量落点**

| 文件 | 容器路径 | 来源 | 对应变量 |
|---|---|---|---|
| `config.toml` | `/opt/categraf/conf/config.toml`（subPath） | ConfigMap `<release>-ksm-config` | 服务端地址/集群名/env/writer/heartbeat |
| `cluster-scrape.yaml` | `/etc/categraf/cluster-scrape.yaml`（subPath） | ConfigMap `<release>-ksm-scrape` | 抓取任务、`external_labels`、remote_write |
| WAL | `/opt/categraf/prometheus-wal`（emptyDir） | — | 重启即丢，不做持久化 |

> 【页面文案（变量提醒）】
> **左侧变量会替换**：`serverAddr`、`clusterName`、`env`、`customLabels`、`remoteWriteUser/Password`、镜像前缀。
> **不可替换**：启动参数固定 `-configs /opt/categraf/conf`；`config.toml` 与 `cluster-scrape.yaml` 都是 subPath 单文件挂载。
> **注意**：本模式 `providers = ["local"]`，**不支持控制台远程下发采集任务**，所有抓取目标只能通过 values 维护。

**验收信号**：`kubectl -n flashcat get cm categraf-ksm-scrape -o yaml` 能看到 `app-metrics` 与自定义 job。

**遇到问题？**
- `extraScrapeConfigs` 写错 → `helm template` 阶段通常不报错，要 `kubectl exec` 进容器看启动日志是否有 yaml 解析错误。
- 同一 target 被抓两次 → 检查是否同时命中 `app-metrics` 与自定义 job。

### 5.5 部署并检查

```bash
# ① 安装
helm upgrade --install categraf \
  oci://registry.flashcat.cloud/public/charts/categraf \
  --version 0.2.3 \
  -n flashcat --create-namespace \
  -f my-values.yaml

# ② 检查 StatefulSet
kubectl -n flashcat get sts categraf-ksm
kubectl -n flashcat get pods -l component=categraf-ksm

# ③ 确认抓取配置已挂进去
kubectl -n flashcat exec categraf-ksm-0 -- cat /etc/categraf/cluster-scrape.yaml | grep job_name
```

**验收清单**：

| # | 信号 | 怎么确认 |
|---|---|---|
| 1 | STS 就绪 | `kubectl get sts categraf-ksm` → `READY 1/1` |
| 2 | KSM 可抓 | 查 `up{job="kube-state-metrics"}` = 1；`kube_pod_status_phase` 有数据 |
| 3 | 场景 A 生效 | 查 `up{job="app-metrics"}` = 1，且带 `service`、`team` 标签 |
| 4 | 场景 B 生效 | 查 `up{job="<自定义 job 名>"}` = 1 |
| 5 | 设备在线 | Flashcat 设备列表出现 `<clusterName>-<release>-ksm-0`（如 `demo-cluster-categraf-ksm-0`），`target_up=2` |
| 6 | 组件（可选） | `up{job="coredns"}`、`up{job="calico"}` 有值 |

> 【页面文案】装完请确认：**`categraf-ksm` 就绪 1/1**、`up{job="kube-state-metrics"}`、`up{job="app-metrics"}`（或你的自定义 job）均为 1、设备在线。

**遇到问题？**
- `up=0` → 端口/路径写错（最常见：写了 Service 端口而不是容器端口）。
- 完全无 target → 业务 Pod 没 `prometheus.io/scrape: "true"`，或自定义 job 的 relabel 没匹配上。
- 改注解后不生效 → 改 Pod 注解会触发滚动重启，等新 Pod Ready 再验。
- `connection refused` → NetworkPolicy 未放通 `flashcat` → 业务命名空间指标端口。
- `REPLICAS 0/1` → 资源不足或 RBAC 缺失，看 `describe pod`。

### 5.6 升级（Helm 升级）

```bash
# ① 备份 values
helm -n flashcat get values categraf > categraf-values.backup.yaml

# ② 升级 Chart 或镜像
helm upgrade categraf \
  oci://registry.flashcat.cloud/public/charts/categraf \
  --version {{新版本}} \
  -n flashcat -f my-values.yaml

# ③ 观察
kubectl -n flashcat rollout status sts/categraf-ksm
```

| 变更 | 生效方式 |
|---|---|
| 加一条 `extraScrapeConfigs` | `helm upgrade` → 重建 `cluster-scrape` ConfigMap → checksum 变化 → STS 重建 Pod（单副本会有数秒采集中断） |
| 换 Chart 版本 | `--version`；配置模板可能变，升级前看变更说明 |
| 回滚 | `helm rollback categraf <REVISION> -n flashcat` |

> 【页面文案（升级说明，与 DS 侧区分）】
> KSM Agent 是**单副本**，升级/改配置期间会有数秒抓取中断，Flashcat 侧表现为短暂缺口，属正常。
> 从 `0.2.1` / `0.2.2-rc.1` 升级且 values 未变更时，需补充执行 `kubectl rollout restart sts/categraf-ksm -n flashcat`。

**验收信号**：`sts` `READY 1/1`，`up` 系列指标恢复。

**遇到问题？**
- 升级后 STS 起不来 → 新 values 的 `extraScrapeConfigs` 语法错误，`kubectl logs` 看 yaml 解析。
- 升级后 KSM 指标断 → 检查 KSM Service 名/端口是否随版本变化（job 的 `regex` 里写死了 `flashcat;categraf-kube-state-metrics;http-metrics`，改 Release 名或命名空间会失配）。

### 5.7 卸载（Helm 卸载）

```bash
helm uninstall categraf -n flashcat --wait

# 保留设备/排障
helm uninstall categraf -n flashcat --no-hooks
```

> 【页面文案】
> 卸载会删除 `categraf-ksm`、`kube-state-metrics` 及配套 ConfigMap；默认会清理本集群 ksmAgent 设备（`operator.cleanup.ksmCategraf`，默认 `true`）。
> 需要保留设备：`--no-hooks` 或先 `cleanup.ksmCategraf: false`。
> 卸载后应用指标的 `up{job="app-metrics"}` 断档属预期。

**验收信号**：`kubectl -n flashcat get sts,deploy,pods` 中无相关资源。

**遇到问题？**
- 卸载后 KSM Service 残留 → KSM 由同一 release 管理，`--no-hooks` 不影响资源删除；残留通常是 `helm uninstall` 失败，重新执行。
- 命名空间残留 → chart 不删 namespace，需手动 `kubectl delete ns flashcat`（确认无其他资源）。

### 5.8 其他说明

| # | 场景 | 做法 | 注意 |
|---|---|---|---|
| 1 | **只想按清单抓**（完全不要规范发现） | `appMetrics.defaultJob.enabled: false` | 只保留 `extraScrapeConfigs` |
| 2 | **只想抓指定命名空间** | 自定义 job 里用 `namespaces.names` 收窄 | 内置 `app-metrics` 是全命名空间，需关掉默认 job |
| 3 | **replicas > 1** | 不建议 | 当前每个副本读同一份 `cluster-scrape.yaml`，会重复抓同一批 target；分片能力未实现 |
| 4 | **STS 缩容后设备残留** | 无自动清理 | Operator 只监听 Node 删除，ksmAgent 设备仅在卸载时清理；需人工在设备列表删除 |
| 5 | **不想部署 KSM** | `kubeStateMetrics.enabled: false` | 需已有 KSM 且 job 的 `regex` 指向它，否则 `up=0` |
| 6 | **组件开关** | CoreDNS/Calico/Cilium 按实际插件只留一个 | 全开会有 `up=0` 的无效 target，噪音大 |
| 7 | **控制平面采集** | `controlPlane.enabled: true` + 放开监听地址（`--bind-address=0.0.0.0`，etcd `--listen-metrics-urls`） | 仅 kubeadm Static Pod 集群适用；二进制部署走 DS 远程下发 |
| 8 | **与 DS 共存** | 同一 release 同时开 `nodeCategraf` 与 `ksmCategraf` | 唯一要防的是"应用指标被 DS 抓"——chart 已把它放在 STS，不要在 DS 侧另配 |
| 9 | **WAL 不持久化** | `prometheus-wal` 是 `emptyDir` | Pod 重建期间本地未发送的数据会丢（秒级） |

---

## 6. 组合态（推荐）：两个模式一起装

### 6.1 页面规则

选「两者都要」时：

- 第 1、2、6、7 节**合并展示**（同一 Chart、同一 Release、同一套依赖与升级/卸载命令），避免用户读两遍。
- 第 3、4、5 节**分两栏/两段**：`节点级（DaemonSet）` 与 `集群级（StatefulSet）`，各自 values 片段并列。
- 第 8 节按合并后的全集出卡片。

### 6.2 合并后的 values（页面直接给这一份）

```yaml
categraf:
  serverAddr: "http://flashcat.example.com:19000"
  clusterName: "demo-cluster"
  env: "prod"
  heartbeatGid: "2"

operator:
  enabled: true
  userToken: "<FLASHCAT_USER_TOKEN>"

nodeCategraf:
  enabled: true
  hostname: nodeName
  hostExec: {enabled: true}
  inputs:
    cadvisor: true
    nodeExporter: true
    hostNative: {enabled: true}

kubeStateMetrics:
  enabled: true

ksmCategraf:
  enabled: true
  replicas: 1
  jobs: {kubeStateMetrics: true}

appMetrics:
  enabled: true
  defaultJob: {enabled: true}
  extraScrapeConfigs: []

kubeProxy: {enabled: true}
coreDns: {enabled: true}
networkPlugin:
  calico: {enabled: true}
  cilium: {enabled: false}
controlPlane: {enabled: false}
```

### 6.3 部署与检查（合并版）

```bash
helm upgrade --install categraf \
  oci://registry.flashcat.cloud/public/charts/categraf \
  --version 0.2.2 -n flashcat --create-namespace -f my-values.yaml

kubectl -n flashcat get ds categraf
kubectl -n flashcat get sts categraf-ksm
kubectl -n flashcat get deploy categraf-kube-state-metrics categraf-operator
```

期望：DS `READY = 节点数`；STS `1/1`；KSM/Operator 各 `1/1`。

---

## 7. 依赖与版本策略（含 Helm `latest` 的结论）

### 7.1 依赖打包策略（页面第 1 节的统一口径）

| 类别 | 是否打包 | 页面怎么说 |
|---|---|---|
| Helm Chart（`.tgz`） | ✅ 打进离线包 | "随离线包提供，历史版本在官网" |
| 4 个容器镜像 | ✅ 打进离线包（`docker save`/`skopeo`） | "已随离线包提供，内网导入后改镜像前缀即可" |
| 采集 SDK / 语言 Agent / 编译库 | 本方案**不需要** | 明确写"无需 SDK"，减少客户疑虑（APM 场景才需要） |
| 宿主机依赖 | 无（容器内自带） | 唯一要求是 privileged + hostPath |

> 【页面文案】我们会把依赖的 Chart 与镜像一并打包到 Flashcat 离线包中，随产品一起部署到客户内部环境，无需公网下载。历史版本仍在官网下载页。

### 7.2 二进制的 `latest`：保留，且必须显示真实版本

- `latest` 只是**下载文件名**，启动后的真实版本要用 `categraf --version`（或在设备详情看版本）。
- 若页面同时展示"二进制下载"，必须成对展示：`latest（当前 = v0.5.45）`，否则客户拿到 `latest` 无法定位版本。

### 7.3 Helm 的 `latest`：有必要，但只在仓库侧，不进页面命令

**结论：保留 `latest` 标签，但页面命令一律写死 `--version`。**

理由（论证，写给内部评审看）：

| 观点 | 事实 | 判断 |
|---|---|---|
| 没有 `latest`，`helm pull` 首次体验会失败 | Helm 的 OCI 拉取在不写 `--version` 时默认取 `latest` 标签；没有该标签会直接报错 | 保留有实际价值 |
| `latest` 会漂移，不可复现 | 同一页面文案在不同时间装出不同 Chart；`helm get manifest` 无法回溯到底装了什么 | 所以**命令里禁止出现 latest**，页面/文档/工单必须写死版本 |
| `latest` 可能指向测试版 | 已用 `publish-chart.sh` 约束：预发布版本（含 `-`）**永不打 latest**，latest 只指向 GA | 风险已收敛；页面也不必再解释 |
| 需要靠 latest 表达"真实版本" | **不需要**：Chart 自带 `version`（0.2.2）+ `appVersion`（0.5.45），`helm show chart` 即可拿到；二进制才需要"latest 文件名 + 启动后真实版本"这层映射 | Helm 与二进制的语义不同：**Chart 的 latest 只是别名，二进制的 latest 需要运行时探测** |
| 客户内网仓库也打 latest | 会把"Chart 版本"和"镜像版本"解耦，出错难定位 | Chart 已把镜像 tag 写死在 values（不带 latest），内网只需改前缀；页面在离线分支明确"不要用 latest 镜像" |

**页面呈现**（三条，缺一不可）：

1. 版本徽标固定显示 `Chart 0.2.3 · Categraf 0.5.45`，悬浮显示：`latest 当前指向 0.2.2`（数据来自 `helm show chart` 抓取，缓存）。
2. 所有命令块写 `--version {{chartVersion}}`，不出现 `latest`。
3. 版本下拉只列 GA 版本（`0.2.2`、`0.2.1`），RC 版本不出现；"获取最新版本"入口单独一个小链接，文字写明"会随发布变化"。

### 7.4 版本命名与发布纪律（页面"版本说明"折叠区可引用）

- 生产版本不复用、不覆盖重推（同 tag 重推会让 digest 漂移，回滚无法确认内容）。
- 测试候选用 `-rc.N` 后缀，语义上小于正式版。
- 本地 `categraf-0.2.x.tgz` 内部构建**未推送到 OCI 仓库**，页面不能把这些版本号当已发布版本写。

---

## 8. 待确认（产品或后端拍板，影响页面结构）

| # | 问题 | 建议 | 影响 |
|---|---|---|---|
| 1 | 组合态是否作为默认入口 | 是，默认「两者都要」 | 决定第 1/2/6/7 节是否需要合并模板 |
| 2 | 是否代管 `USER_TOKEN` | 不代管，只做前端透传，不落库 | 安全审计 |
| 3 | 离线包下载是否在本页内完成 | 本页只给"如何导入"，下载回官网/制品库 | 避免页面变成大文件分发器 |
| 4 | 是否要暴露 RC 版本给客户 | 不暴露；需要时由技术支持给 `--version` | 版本下拉 |
| 5 | STS 多副本分片是否立项 | 短期锁 `replicas: 1` 并在页面写明 | 5.8 第 3 条 |
| 6 | Operator 是否支持 STS 缩容清理 | 建议立项（当前是能力缺口） | 4.8 第 6 条与 5.8 第 4 条的文案 |
| 7 | 控制台"应用发现"下发能力是否覆盖 STS | 若不覆盖，5.4 的"A 需要 upgrade 吗"要改口径 | 3.4 表 |
| 8 | `categraf-ksm` 的 `serviceName` 未创建 headless Service | 低优先，补一个 headless Service 更规范 | 无用户可见影响 |

---

## 9. 页面文案速查（可直接粘贴）

| 位置 | 文案 |
|---|---|
| 顶部副标题 | 选择部署形态，按指引完成 Kubernetes 接入。全程约 10 分钟。 |
| 模式卡片 · DS | **节点采集（DaemonSet）**：每节点一个 Categraf，采集主机、kubelet/cAdvisor、kube-proxy，支持任务通道与服务拓扑。 |
| 模式卡片 · STS | **集群与应用采集（StatefulSet）**：集群级一个 Categraf，采集 KSM、应用指标与 K8s 组件，统一出口不重复。 |
| 模式卡片 · 两者 | **两者都要（推荐）**：同一 Release 同时部署，覆盖最全。 |
| 环境要求备注 | 不满足此环境要求，请联系 Flashcat 技术人员提供支持。 |
| 配置节提示 | 左侧变量会实时替换下方片段；`{{}}` 提示项必须替换后再执行。 |
| 部署节提示 | 命令可直接复制执行；离线环境请使用第 ①段第二条命令。 |
| 卸载节提示 | 默认会清理本集群在 Flashcat 上的设备；需要保留请用 `--no-hooks`。 |
| 底部完成态 | 接入完成。下一步：配置告警规则 / 开启服务拓扑 / 接入应用 APM。 |

---

## 10. 页面文案的密度约束（v2 调整）

第一版把"设计文档里的完整信息"直接平铺到了页面上，结果是 1 相关依赖 8 行表格、3 功能说明 5 列表格 + 两张对照表，用户看一眼就晕。已按下面三条重构（Demo 已落地）：

| 规则 | 具体要求 | 为什么 |
|---|---|---|
| 正文 ≤ 4 条 | 每节正文只留 3～4 条 bullet，单条 ≤ 25 字 | 用户是"边看边做"，不是来读文档的 |
| 长表进折叠 | 表格 > 5 行或 > 3 列，收进 `<details>`；正文只给结论 | 信息不删，只降层级；需要时才展开 |
| 验收项可观察 | 只写"指标有数 / 状态 Ready / 设备在线"，删掉"请你检查 kubectl 版本"这类动作项 | 动作项无法打勾，只增加负担 |

### 10.1 三节的实际改法

| 节 | 改前 | 改后 |
|---|---|---|
| 1 相关依赖 | 8 行表（依赖/版本/说明） | 一句话结论 + 3～4 条 bullet（Chart、镜像、Helm）+ `依赖明细` 折叠表 |
| 2 运行环境要求 | 10 行表 + 一条"kubectl/helm 版本"验收项 | 3 条硬要求 bullet + 固定提示语 + `完整要求` 折叠表；**删除版本检查项** |
| 3 功能说明 | 5 列能力表 + 6 行能力边界表 + 4 行场景对照表 | 4 条 bullet（每项一句话）+ 一句边界提醒 + `两类应用怎么接` 折叠区 |

### 10.2 折叠区放什么（别把信息丢掉）

- 镜像地址、OCI 路径、可选组件（operator）→ 依赖明细
- Pod Security、taint、入向端口、资源规格 → 完整要求
- 两场景的具体做法（注解写法、`extraScrapeConfigs`）→ 两类应用怎么接

正文只回答"要不要准备""能不能装"，折叠区回答"具体是什么"。

> 本文档 4.1～4.3 / 5.1～5.3 里的表格，就是上面的"折叠明细"内容，不再作为页面正文直接展示；页面正文以 Demo 为准。

## 11. 页面形态调整：8 节说明页 → 配置页（v3）

参考页是个**配置页**，不是文档页：用户只做三件事——填参数、看配置、复制命令。第一版按 8 节展开（依赖/环境/功能/配置/部署/升级/卸载/其他）对首次接入确实偏重，已按下面的取舍重做，Demo 与交付说明均已切到新版。

### 11.1 保留 / 移除

| v2 的 8 节 | v3 处理 | 原因 |
|---|---|---|
| 4 配置文件 | **保留**，成为页面主体 ① | 用户真正要复制的东西 |
| 5 部署并检查 | **保留**，成为主体 ② + 步骤 2 校验 | 部署命令与验收是闭环 |
| 2 运行环境要求 | **精简为页面首节** | 只保留 K8s 版本 / Helm / 网络三项 + 检查命令；Pod Security、taint、资源规格等细节不进页面 |
| 1 相关依赖 | **移除**，只留左栏一行「镜像与 Chart 由管理员预置」 | 依赖不该让用户准备 |
| 3 功能说明 | **移除** | 卖点文案放官网/方案 PPT，不进接入流程 |
| 6 升级 / 7 卸载 | **移到第三个 Tab「升级与卸载」** | 属于安装后的高频运维动作，藏在文档里不好找；独立 Tab 不影响安装主流程 |
| 8 其他说明 | **移除** | 边缘场景，客服话术覆盖 |

### 11.2 页面结构（v3）

```
接入对象（Categraf / APM）
  └─ ① 安装与配置 ─┬─ 左：部署方式(在线/离线)、集群名、命名空间、环境、采集模式、上报地址、采集间隔
                    （离线时额外展开：Chart 包地址、镜像仓库前缀）
                   └─ 右：① 准备配置(values.yaml) ② 部署并检查(helm + kubectl)
  └─ ② 接入校验（设备在线、指标有数）
  └─ ③ 升级与卸载（备份→upgrade→rollout→rollback；uninstall / --no-hooks / 关清理）
```

### 11.3 两条不能因为"简化"而丢的代码事实

| 事实 | 后果 | 页面处理 |
|---|---|---|
| `operator.enabled` 默认 `true` 且 `userToken` 必填 | 不写会直接安装失败 | 生成的 values 固定写 `operator.enabled: false`，注释说明由管理员开启 |
| `nodeCategraf` 与 `ksmCategraf` 是两个独立开关 | 单选模式会丢一半能力 | 采集模式做成**可多选**，支持"两者都要" |

### 11.4 本文档后续定位

第 4～6 章（依赖、环境、功能）不再作为页面内容，转为**实施/售后手册**素材：客户问"要多少资源""为什么不支持 Windows""能不能只采容器"，答案在这里，不在页面上。

### 11.5 在线 / 离线是一个独立维度（v3.1）

部署方式不是"参数之一"，而是**决定两件事的分支**：Chart 从哪来、镜像从哪来。两条链路必须分开生成，不能靠用户自己改：

| | 在线 | 离线 |
|---|---|---|
| Chart 来源 | `oci://registry.flashcat.cloud/public/charts/categraf` + `--version 0.2.2` | 用户填的包路径（`./categraf-0.2.2.tgz` 或 `http(s)://…`） |
| 镜像 | Chart 默认（`registry.flashcat.cloud/public/…`），**values 不写 image** | 用户填的仓库前缀，**values 覆盖 3 处 image** |
| 前提 | 节点可访问公网 | 镜像已推送内网仓库，tag 与 Chart 版本一致 |

两个容易错的细节：

1. **节点镜像与集群镜像 tag 不同**：`categraf_ent:servicemap-v0.5.45`（节点，含拓扑）vs `categraf_ent:v0.5.45`（集群）。
2. **kube-state-metrics 多一层目录**：`<前缀>/kube-state-metrics/kube-state-metrics:v2.19.1`，拍平会拉不到。

页面交互上，离线时展开「Chart 包地址」「镜像仓库前缀」两个字段并纳入必填校验；在线时收起且不参与校验，避免用户被无关字段干扰。

离线还多一节「同步 Chart 与镜像」：给出 `helm pull` 与 `skopeo copy --all` 命令，按当前勾选的采集模式与 Operator 开关动态生成镜像条数——物料清单必须和 values 里的 image 覆盖一一对应，否则会出现"同步了用不上 / 用了没同步"。

---

### 11.6 可选配置：把「是否…」从主表单里挪走（v3.2）

主表单只留 7 个必填/常改参数，其余**布尔开关全部收进折叠的「可选配置」**，默认收起、默认值即大多数客户的最优值。折叠标题右侧有徽标：未改动显示「默认」，改动后显示「已改 N 项」。

| 开关 | 默认 | 写入 values | 备注 |
|---|---|---|---|
| 自定义标签 | 关 | `categraf.customLabels`（key/value 多行） | 开启后才显示编辑器 |
| 安装 Operator | 关 | `operator.enabled` + `userToken` + `cleanup.*` | 开启后 Token 必填，未填则禁用下一步 |
| 卸载时清理设备 | 开 | `operator.cleanup.nodeCategraf` / `ksmCategraf` | 嵌在 Operator 下 |
| 安装 kube-state-metrics | 开 | `kubeStateMetrics.enabled` | 集群已有 KSM 时关 |
| 启用应用指标发现 | 开 | `appMetrics.enabled` | 关时必须显式写 false（Chart 默认 true） |
| 只采集带注解的服务 | 开 | `appMetrics.defaultJob.enabled` | 关掉后仅保留自定义任务 |
| 主机原生指标 | 开 | `nodeCategraf.inputs.hostNative.enabled` | 影响 Flashcat 主机大盘 |
| kubelet / cAdvisor | 开 | `nodeCategraf.inputs.cadvisor` | 关掉后容器指标消失 |
| kube-proxy | 开 | `kubeProxy.enabled` | 依赖 hostNetwork |
| CoreDNS | 开 | `coreDns.enabled` | |
| 网络插件 | **不采集** | `networkPlugin.calico/cilium.enabled` | 下拉三选，避免 `up=0` 无效目标 |

三条设计原则：

1. **按模式过滤**：只有 DaemonSet 时隐藏 KSM/appMetrics/CoreDNS/网络插件；只有 STS 时隐藏主机三类。用户看不到不生效的开关。
2. **默认值要安全**：网络插件 Chart 默认 calico/cilium 全开，客户集群只可能有一种，全开会产无效目标，所以页面默认「不采集」，让用户显式选。
3. **危险开关带依赖**：Operator 需要 Token，开启后若 Token 为空直接禁用下一步按钮，避免"装上去但 operator 崩溃"的现场。

> 实现细节：`appMetrics` 与 `kubeStateMetrics` 必须**显式写 true/false**。Chart 里 `appMetrics.enabled` 默认 `true`，页面若"关掉时不写"，用户以为关了其实没关——这是最容易漏的一处。

### 11.7 增加 A/B/D 组参数（v3.3）

> 复核后删掉了一项：「容忍 NoExecute 污点」。原因：DaemonSet 控制器已自动给 DS Pod 注入 `not-ready:NoExecute` / `unreachable:NoExecute` 容忍，最常见的两类本就覆盖；剩下的自定义 NoExecute 语义是"把节点腾空"，采集 Pod 赖着不走反而违背运维意图；而且实现上是全量覆盖 `tolerations`，会冲掉客户自有配置。真有特殊 taint，用自定义 tolerations 字段比开关更合适。

按"默认值对 80% 客户正确 + 改错后果可控"筛过之后，补了 11 个参数。全部使用 `helm template` 实测渲染通过（含 tolerantions / resources / controlPlane / extraScrapeConfigs / heartbeatGid）。

| 组 | 参数 | 位置 | values key |
|---|---|---|---|
| A | 业务组 | 主表单 | `categraf.heartbeatGid`（渲染进心跳 URL `?gid=`） |
| A | 自定义采集任务 | 可选配置（YAML 文本域） | `appMetrics.extraScrapeConfigs` |
| A | 上报标识 | 可选配置（下拉） | `nodeCategraf.hostname` |
| A | 远程写认证 | 可选配置（账号+密码） | `categraf.remoteWriteUser/Password` |
| B | 资源规格 | 可选配置（小 / 中·推荐 / 大 / 自定义） | 小·大：三个工作负载；中：仅覆盖 `ksmCategraf.resources.limits.memory: 2Gi`；自定义：按启用模式分三组 |

> `1.5Gi` 是 Chart 0.2.2 的默认内存上限，语法合法（等于 1536Mi），但和其他二进制整数值（512Mi / 1Gi / 2Gi）风格不一致，且 KSM Agent 在对象多的集群里确实吃内存，故页面统一提到 2Gi。中档用**部分覆盖**而非整块重写，Helm 会递归合并，cpu 与 requests 仍取 Chart 默认——已用 `helm template` 验证渲染结果为 `cpu: 1000m / memory: 2Gi`。
| B | 写入批量 | 可选配置 | `categraf.writer.batch` |
| B | 控制平面采集 | 可选配置 | `controlPlane.enabled` |
| D | 合规模式（非特权） | 可选配置 | `securityContext.privileged: false` **+** `hostExec.enabled: false` |
| D | 集群侧抓取间隔 | 可选配置 | `categraf.prometheus.scrapeInterval`（待 Chart 支持） |

两个实现上的坑，已写进交付说明：

1. **合规模式必须同时关 hostExec**。模板里 `hostExec.enabled: true` 会强制 `privileged: true`，只改 securityContext 不生效——这是最容易做成"看起来生效其实没生效"的开关。
2. **`split` 依赖 Chart 变更**。0.2.2 的 `templates/_config.tpl` 第 84 行是硬编码 `scrape_interval: 15s`，`categraf.config.interval` 只影响 input 周期。要让"KSM 60s"成立，需要：

```diff
-  scrape_interval: 15s
+  scrape_interval: {{ int (default 15 (dig "prometheus" "scrapeInterval" 0 .Values.categraf)) }}s
```

页面已按新 key 生成（低版本 chart 会忽略该 key，不报错），但这属于**发版变更**：需要升 Chart 版本、重跑模板回归、更新 repo 文档，因此单独走一次发布，未与本次页面改动混在一起。

---

## 附：与参考页 8 节的对应关系

| 参考页小节 | 本设计 | 差异 |
|---|---|---|
| 1 相关依赖 | 4.1 / 5.1 | 补"离线包 + 历史版本在官网 + latest 语义" |
| 2 运行环境要求 | 4.2 / 5.2 | 补 PSA、taint、入向端口、容量 |
| 3 功能说明 | 4.3 / 5.3 | 每个能力挂到具体 values 开关，标注"需在控制台开启" |
| 4 配置文件 | 4.4 / 5.4 | 补左栏变量注入矩阵、启动参数不可改、subPath 挂载约束 |
| 5 部署并检查 | 4.5 / 5.5 | 检查项做成可勾选清单，含指标级验证 |
| 6 升级 | 4.6 / 5.6 | 补 checksum/rollout restart 的坑、回滚 |
| 7 卸载 | 4.7 / 5.7 | 补设备清理决策（--no-hooks / cleanup 开关） |
| 8 其他说明 | 4.8 / 5.8 | 补 Operator 能力边界、STS 缩容缺口、多 Release 隔离 |
