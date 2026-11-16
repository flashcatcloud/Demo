# K8s 接入 Categraf · 前端交付说明（配置页版）

> 配套：[`K8s接入Categraf-页面demo.html`](./K8s接入Categraf-页面demo.html)
> 可直接跳状态：`?deploy=online|offline`、`?mode=ds|sts|both`、`?step=1|2`
> 旧版「8 节说明页」在 [`_archive/`](./_archive/)，不要按它做。
> 数据来源：Chart `categraf-0.2.3`（appVersion `0.5.45`），values key 与工作负载名均取自真实渲染。

---

## 1. 页面只做三件事

| # | 用户动作 | 页面产物 |
|---|---|---|
| 1 | 填必要参数 | 左侧表单 |
| 2 | 看配置 | 右侧 ① 准备配置：`values.yaml` 实时生成 |
| 3 | 复制命令 | 右侧 ② 部署并检查：安装命令 + 就绪检查 |

**不展示**：依赖清单、运行环境要求、功能说明、升级/卸载、故障排查。这些由管理员预置或支持兜底，页面只在左栏底部留一行「镜像与 Chart 由平台管理员预置」。

---

## 2. 页面结构

```
┌─ 接入对象 ───────────────────────────────────────────────────┐
│ [Categraf 主机·容器·中间件 ✓]      [应用性能分析接入 · 即将支持] │
└──────────────────────────────────────────────────────────────┘
┌─ ① 安装与配置 ──┬─ ② 接入校验 ──┬─ ③ 升级与卸载 ───────────────┐
│ 部署环境   [主机×][K8s✓]     │ ① 准备配置   values.yaml       │
│ 部署方式   [在线✓][离线]      │                              │
│   ├ Chart 包地址 ※仅离线      │ ② 部署并检查  helm + kubectl   │
│   ├ 镜像仓库前缀 ※仅离线      │                              │
│ 集群名称   prod-k8s-01        │                              │
│ 命名空间   flashcat           │                              │
│ 环境       prod               │                              │
│ 采集模式   DaemonSet ✓        │                              │
│           StatefulSet         │                              │
│ 上报地址   http://…           │                              │
│ 采集间隔   15 s               │                              │
│ ▸ 可选配置（默认收起）        │                              │
├─────────────────────────────┴──────────────────────────────┤
│ [上一步]                                    [进入接入校验 →] │
└────────────────────────────────────────────────────────────┘
```

---

## 3. 参数契约

**必填项用红色 `*` 标注**（表单顶部有一行图例）：`集群名称`、`命名空间`、`上报地址` 恒为必填；离线模式下 `Chart 包地址`、`镜像仓库前缀` 也必填；`API Token` 仅在开启 Operator 时必填（关闭时不标红）。

## 3. 参数契约

| key | 标签 | 控件 | 默认 | 校验 | 写入位置 |
|---|---|---|---|---|---|
| `deployEnv` | 部署环境 | 两段按钮 | `k8s` | 主机/虚拟机本期禁用 | 不影响输出 |
| `online` | 部署方式 | 两段按钮 | `true`（在线） | — | 决定命令形态与是否覆盖镜像 |
| `chartPath` | Chart 包地址 | input（仅离线可见） | `./categraf-0.2.3.tgz` | 离线时非空 | 安装命令的 Chart 位置 |
| `regPrefix` | 镜像仓库前缀 | input（仅离线可见） | `harbor.internal/flashcat` | 离线时非空 | 4 处 `image` 覆盖 |
| `cluster` | 集群名称 | input | `prod-k8s-01` | 非空 | `categraf.clusterName` + `cluster` 标签 |
| `ns` | 命名空间 | input | `flashcat` | DNS-1123 | `helm -n`、`kubectl -n` |
| `env` | 环境 | select | `prod` | — | `categraf.env` |
| `gid` | 业务组 ID | input | 空（不分组） | — | `categraf.heartbeatGid` |
| `operator` | 安装 Operator | 开关 | **开** | — | `operator.enabled` |
| `opToken` | API Token | input | 空 | 开关开启时必填 | `operator.userToken` |
| `ds` / `sts` | 采集模式 | 两张卡（**多选**） | **两张都选中** | 至少一种 | `nodeCategraf.enabled` / `ksmCategraf.enabled` |
| `addr` | 上报地址 | input + 清空 + 预设 | `http://flashcat.internal:19000` | 非空 | `categraf.serverAddr` |
| `interval` | 采集间隔 | select | `15` | — | `categraf.config.interval` |

Operator 块内还有一个二级开关「卸载Chart包时自动清理设备」→ `operator.cleanup.nodeCategraf` / `ksmCategraf`。它属于主表单控件，**不计入「已改 N 项」**——徽标只统计「可选配置」里的改动。

**「安装方式」不再是独立字段**：产品只有 Helm 一种安装方式，留在表单里是个死控件。改为部署方式下面的说明文字「安装方式固定为 Helm Chart」。

**自定义规则输入框要能容错**：用户很可能把整段 `appMetrics:` 配置粘进来（实测过，直接粘会让 `extraScrapeConfigs` 变成 map，Chart 报 `appMetrics.extraScrapeConfigs must be a list`）。所以前端必须先规范化再写入：

1. 找到 `extraScrapeConfigs:` 行，只取它之后的内容
2. 计算非空行的最小缩进并整体去掉（兼容粘自带缩进的情况）
3. 去掉首尾空行
4. 规范化后仍不以 `-` 开头的，给出黄色警示（不阻断，让用户自己判断）

### 3.1 可选配置（折叠区：10 个开关 + 1 个下拉）

默认收起，展开才改；徽标显示「默认 / 已改 N 项」。**默认值即大多数客户的最优值**，不展开也能直接用。

| key | 标签 | 默认 | 出现在 | 写入 values |
|---|---|---|---|---|
| `labels` | 设备自定义标签 | 关 | 全部 | `categraf.customLabels`（开时显示 key/value 编辑，可增删多行） |
| `ksm` | 采集 K8s 对象状态 | 开 | 有 STS | `kubeStateMetrics.enabled` |
| `appMetrics` | 采集应用指标 | 开 | 有 STS | `appMetrics.enabled` |
| `defaultJob` | 按注解自动发现 | 开 | appMetrics 开启时 | `appMetrics.defaultJob.enabled` |
| `hostNative` | 采集Categraf原生主机指标 | 开 | 有 DS | `nodeCategraf.inputs.hostNative.enabled` |
| `cadvisor` | 采集容器指标 | 开 | 有 DS | `nodeCategraf.inputs.cadvisor` |
| `kubeProxy` | 采集 Kube-proxy 指标 | 开 | 有 DS | `kubeProxy.enabled` |
| `coreDns` | 采集 CoreDNS 指标 | 开 | 有 STS | `coreDns.enabled` |
| `networkPlugin` | 采集网络插件指标（下拉：不采集 / Calico / Cilium） | 不采集 | 有 STS | `networkPlugin.calico.enabled` / `cilium.enabled` |
| `extraJobs` | 按自定义规则采集（开关 + YAML 文本域） | 关 | 有 STS | 规范化后缩进写入 `appMetrics.extraScrapeConfigs` |
| `controlPlane` | 采集控制平面指标 | 关 | 有 STS | `controlPlane.enabled`（实测：apiserver 开箱可用；scheduler/controller-manager/etcd 需放开监听，否则 up=0） |
| `ident` | 设备标识（下拉） | 节点名 | 有 DS | `nodeCategraf.hostname` = `nodeName` 或 `"${cluster}-${nodeName}"` |
| `remoteWrite` | 写入认证（用户名/密码） | `user001` / 空 | 有 STS | 密码非空才写 `remoteWriteUser/Password` |
| `imgVer` | Categraf 版本 | input | `0.5.45` | 非空 | `nodeCategraf.image`（`servicemap-v{ver}`）、`ksmCategraf.image`（`v{ver}`） |
| `ksmVer` | kube-state-metrics 版本 | input | `2.19.1` | 装了 KSM 时非空 | `kubeStateMetrics.image` |
| `opVer` | Operator 版本 | input | `0.0.7` | 开了 Operator 时非空 | `operator.image` |
| `res` | 资源规格（下拉：小 100m/256Mi / 中 200m/512Mi / 大 500m/1Gi / 自定义） | 中·推荐 | 全部 | 小/大：写三个工作负载（node / ksm agent / kube-state-metrics）；中：**只覆盖 `ksmCategraf.resources.limits.memory: 2Gi`**，其余不写；自定义：按启用模式分别写三处 |
| `batch` | 写入批量（下拉） | 默认 | 全部 | `categraf.writer.batch` |
| `split` | 集群侧抓取间隔（开关 + 下拉） | 关 | 有 STS | `categraf.prometheus.scrapeInterval` |
| `compliant` | 非特权模式 | 关 | 有 DS | `securityContext.privileged: false` + `hostExec.enabled: false` |

四条关键约束：

- **合规模式必须同时关 `hostExec`**：chart 模板里 `hostExec.enabled: true` 会强制把 `privileged` 设回 `true`，只改 securityContext 不生效。
- **`split`（集群侧间隔）自 Chart 0.2.3 起生效**：0.2.3 之前 `cluster-scrape.yaml` 的 `scrape_interval` 是硬编码 15s；现在由 `categraf.prometheus.scrapeInterval` 控制。页面直接输出该 key。
- **自定义采集任务要自动开 appMetrics**：只要文本域有内容，即使「启用应用指标发现」是关的，也应输出 `appMetrics.enabled: true`，否则任务无效。
- **资源规格只在非「中」时展开**：中档就是 chart 默认值，写出来只会让 values 变长。

两条设计约束：

1. **开关按模式过滤显示**：只有 DaemonSet 时，STS 相关开关（KSM / appMetrics / CoreDNS / 网络插件）隐藏；反之亦然。避免用户看到不生效的开关。
2. **网络插件默认「不采集」**：Chart 默认 calico/cilium 都是 `true`，客户集群只会有一种是真实的，全开会产出 `up=0` 的无效目标。让用户显式选。

---

## 4. 配置生成规则

### 4.1 固定前缀（两种部署方式都有）

```yaml
categraf:
  serverAddr: "{{addr}}"
  clusterName: "{{cluster}}"
  env: "{{env}}"
  config:
    interval: {{interval}}

operator:
  enabled: false          # 设备自动清理需配置 Token，由管理员开启
```

`operator.enabled` **必须显式写**：页面默认开启，此时必须带 `userToken`（未填则主按钮禁用，避免装出跑不起来的 Operator）；用户关掉时写 `enabled: false`，不能省略——Chart 默认是 `true` 且 Token 必填，漏写会安装失败。

### 4.2 采集模式决定启停的组合

| 组合 | 追加 |
|---|---|
| 仅 DaemonSet | `nodeCategraf.enabled: true`；`ksmCategraf.enabled: false`；`kubeStateMetrics.enabled: false` |
| 仅 StatefulSet | `nodeCategraf.enabled: false`；`ksmCategraf.enabled: true` + `replicas: 1`；`kubeStateMetrics.enabled: true`；`appMetrics.enabled: true` + `defaultJob.enabled: true` |
| 两者都要 | 两边都 `true`（KSM 同理） |

### 4.3 镜像版本是参数，不是写死的

三个版本输入框决定镜像 tag：

| 参数 | 影响的镜像 | tag 规则 |
|---|---|---|
| `imgVer` | 节点采集 + 集群采集（同一个基础版本、不同变体） | `categraf_ent:servicemap-v{ver}` / `categraf_ent:v{ver}` |
| `ksmVer` | kube-state-metrics | `kube-state-metrics/kube-state-metrics:v{ver}` |
| `opVer` | categraf-operator | `categraf-operator:{ver}` |

**写入规则**（很容易做错）：

- **在线模式**：版本等于默认值 → **不写 image**，沿用 Chart 默认；改了版本 → 显式写 `registry.flashcat.cloud/public/...`。否则用户改了版本也会被 Chart 默认值盖掉。
- **离线模式**：**始终写 image**，前缀取「镜像仓库前缀」，tag 取上面的版本参数。
- 节点与集群两个镜像必须是**不同 tag**（`servicemap-` 前缀只在节点侧），不要用同一个值复制粘贴。
- 同步物料（§5.0）与 values 用同一套版本，保证"同步什么就装什么"。

### 4.3 离线部署才追加镜像覆盖

在线部署用 Chart 默认镜像（`registry.flashcat.cloud/public/...`），**不写 image**；离线部署把 3 处镜像改到内网仓库：

```yaml
nodeCategraf:
  enabled: true
  image: "{{regPrefix}}/categraf_ent:servicemap-v0.5.45"

ksmCategraf:
  enabled: true
  replicas: 1
  image: "{{regPrefix}}/categraf_ent:v0.5.45"
  resources:               # 中档也写：只覆盖内存上限（Chart 默认 1.5Gi → 2Gi）
    limits:
      memory: 2Gi
kubeStateMetrics:
  enabled: true
  image: "{{regPrefix}}/kube-state-metrics/kube-state-metrics:v2.19.1"
```

### 4.4 可选配置对应的 values 片段

```yaml
categraf:
  heartbeatGid: "2"            # 填了业务组才出现
  customLabels:                # 仅开启「自定义标签」且有 key 时出现
    region: "cn-shanghai"
  remoteWriteUser: "user001"   # 密码非空才出现
  remoteWritePassword: "***"
  writer:
    batch: 5000                # 选了非默认批量才出现
  prometheus:
    scrapeInterval: 60         # 开启「集群侧抓取间隔」（需 Chart ≥ 0.2.3）

operator:                  # 仅开启「安装 Operator」
  enabled: true
  userToken: "<Token>"
  cleanup:
    nodeCategraf: true
    ksmCategraf: true      # 仅装了 STS 时写 true

nodeCategraf:              # 仅 DaemonSet
  hostname: nodeName       # 或 "${cluster}-${nodeName}"（此时服务拓扑不可用）
  securityContext:         # 仅在「合规模式」出现
    privileged: false
  hostExec:                # 合规模式必须同步关掉，否则 privileged 会被模板强制改回 true
    enabled: false
  inputs:
    cadvisor: true
    hostNative:
      enabled: true
  resources:               # 小/大档位或自定义（节点分组）时出现
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
kubeProxy:
  enabled: true

kubeStateMetrics:          # 仅 STS，受「安装 kube-state-metrics」控制
  enabled: true
  resources:               # 小/大档位或自定义时出现
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
appMetrics:
  enabled: true
  defaultJob:
    enabled: true
  extraScrapeConfigs:      # 自定义采集任务，按 4 空格缩进原样写入
    - job_name: redis-exporter
      kubernetes_sd_configs:
        - role: endpoints
coreDns:
  enabled: true
networkPlugin:
  calico:
    enabled: false
  cilium:
    enabled: false
```

注意：

- **节点镜像与集群镜像不是同一个 tag**（`servicemap-` 前缀只在节点侧）。
- `kube-state-metrics` 多一层目录（`kube-state-metrics/kube-state-metrics`），别拍平。
- operator 关闭时不覆盖它的镜像。
- 离线时 values 顶部加一行注释 `# 离线部署：Chart 与镜像均来自内网`，便于排障时一眼识别。

---

## 5. 命令生成规则

### 4.5 values.yaml 怎么到用户手里

命令里写的是 `-f values.yaml`，所以页面必须回答「这个文件从哪来」。现在三处闭环：

1. **步骤 ② 标题**：明确写「点『↓ 下载』存成 values.yaml，或复制后自行保存」
2. **代码块右上角两个按钮**：`⧉ 复制`（剪贴板）+ `↓ 下载`（`Blob` + `a[download]`，文件名固定 `values.yaml`）
3. **代码块下方提示**：保存位置是"与部署命令同一个目录"，并给出漏存时的报错 `open values.yaml: no such file`；另给一句 `--set` 的备选方式

部署命令首行也加了注释 `# 前提：values.yaml 已在当前目录`，避免用户直接从中间开始复制。

### 4.9 步骤 1 的首节：环境要求

页面在「安装与配置」最前面固定给一节环境要求，只保留装之前必须确认的三项：

| 项 | 内容 |
|---|---|
| Kubernetes | **1.19 ~ 1.37**，页面在区间后灰字备注「1.19 以下未验证」；不写验证清单 |
| Helm / kubectl | Helm ≥ 3.0；kubectl 能连上目标集群 |
| 网络 | 节点能访问左栏填写的 Flashcat 地址 |

配合一个「检查命令」代码块：`kubectl version --short`、`helm version --short`、`kubectl get nodes --no-headers | wc -l`（最后一条用于部署后核对 DS 副本数）。

小节编号因此变为：在线 1 环境要求 / 2 准备配置 / 3 部署并检查；离线 1 环境要求 / 2 同步 Chart 与镜像 / 3 准备配置 / 4 部署并检查。

### 5.0 离线多一步：同步 Chart 与镜像

离线模式下，步骤 1 会比在线多出一节「① 同步 Chart 与镜像」，全部命令按当前勾选模式动态生成：

| 块 | 内容 | 生成规则 |
|---|---|---|
| 同步 Chart | `helm pull oci://…/categraf --version 0.2.3`；可选 `helm registry login/push` 到内网 OCI | 固定 |
| 同步镜像 | 两种实现，小切换器默认 `docker pull / tag / push`，备选 `skopeo` | 条目数按模式过滤：DS→节点镜像；STS→集群镜像（+KSM 镜像，若未关）；Operator 开→operator 镜像 |

两种实现都带上前置说明：

- **skopeo**：`skopeo login` + 提示「HTTP 或自签证书时给每条 copy 加 `--dest-tls-verify=false`」+ `skopeo copy --all`（多架构一起搬）
- **docker**：`docker login` + `pull / tag / push` 三件套 + 提示「`docker pull` 只拉当前机器架构，多架构需 `--platform` 再走一遍」

补充说明（页面 hint）：没有 skopeo 时用 docker pull/tag/push；完全没有内网仓库时用 docker save/load；已推送到内网 OCI 时把左栏「Chart 包地址」改成 `oci://<仓库>/charts/categraf`，部署命令会自动带 `--version`。

### 5.1 在线

```bash
# 从公网仓库拉取 Chart
helm upgrade --install categraf \
  oci://registry.flashcat.cloud/public/charts/categraf \
  --version 0.2.3 \
  -n {{ns}} --create-namespace \
  -f values.yaml
```

### 5.2 离线

```bash
# 使用离线包内的 Chart（无需访问公网）
helm upgrade --install categraf {{chartPath}} \
  -n {{ns}} --create-namespace \
  -f values.yaml
```

`{{chartPath}}` 支持相对路径（`./categraf-0.2.3.tgz`）和 `http(s)://` 地址，Helm 都认。

### 5.3 就绪检查（两种部署方式都一样）

| 模式 | 追加 |
|---|---|
| DaemonSet | `kubectl -n {{ns}} rollout status ds/categraf`；`kubectl -n {{ns}} get pods -o wide -l component=categraf` |
| StatefulSet | `kubectl -n {{ns}} rollout status sts/categraf-ksm`；`kubectl -n {{ns}} get pods -l component=categraf-ksm` |

Release 名固定 `categraf`（工作负载名依赖它），不暴露给用户；版本号写死，不动态拼。

---

### 5.4 步骤 3「升级与卸载」生成规则

独立 Tab，不占安装流程。命令按部署方式与采集模式动态生成：

| 块 | 内容 | 变量点 |
|---|---|---|
| 升级 | `helm get values` 备份 → `helm upgrade` → `rollout status`（按启用模式输出 ds/sts 两类）→ `helm rollback` | Chart 来源（OCI + `--version 0.2.3` / 离线包路径）、命名空间 |
| 卸载 | `helm uninstall --wait`（默认，触发设备清理）；`--no-hooks`（保留设备）；或升级前 `--set operator.cleanup.*=false` | 命名空间、Chart 来源 |

页面提示固定一句：清理只作用于本集群（按集群名匹配），不删业务组、不影响其他集群；清理卡住多半是 Flashcat 不可达或 token 无效，可用 `--no-hooks` 跳过 hook。

## 6. 步骤 2「接入校验」生成规则

| 模式 | 校验项 |
|---|---|
| 都有 | 设备在线：设备列表出现该集群设备，`target_up = 2` |
| DaemonSet | `node_load1{cluster="…"}` 有数据；`container_cpu_usage_seconds_total{cluster="…"}` 有数据 |
| StatefulSet | `kube_pod_status_phase{cluster="…"}` 有数据；`up{job="app-metrics"}` = 1 |

设备名：仅 DS → 每台节点一个（名称即节点名）；仅 STS → `<cluster>-categraf-ksm-0`；两者 → 两种都有。

---

## 7. 交互清单

| # | 交互 | 规则 |
|---|---|---|
| 1 | 参数改动 | `input`/`change` 即时重渲染 values 与命令，无保存按钮 |
| 2 | 部署方式切换 | 在线/离线二选一；选离线时展开两个路径字段，选在线时收起且不参与校验 |
| 3 | 采集模式 | 多选，至少一种；取消最后一种时忽略点击 |
| 4 | 上报地址清空 | `✕` 清空后主按钮禁用 |
| 5 | 主按钮 | 1→2「进入接入校验 →」、2→3「查看升级与卸载 →」、3「完成」（禁用）；必填缺失时禁用 |
| 6 | 上一步 | 步骤 1 禁用；步骤 2 可回退 |
| 7 | 复制 | 复制 `<pre>` 文本，成功显示「已复制」1.2s |
| 8 | URL 预设 | `?deploy=`、`?mode=`、`?step=` |
| 9 | `?` 悬浮说明 | 移入显示、移出消失；浮层在图标下方展开，深色卡片，`pointer-events:none` 不挡点击 |
| 10 | `↓ 下载` values.yaml | 仅 values 代码块有；下载文件名固定 `values.yaml`，内容取当前渲染结果 |
| 9 | `?` 悬浮说明 | 鼠标移入显示、移出不显示；浮层在图标下方展开，深色卡片、不拦截点击 |

---

## 8. 内容红线

1. **不要加回依赖清单**，管理员预置，页面只留一行说明。
2. **不要暴露启动参数**（固定 `-configs /opt/categraf/conf`）。
3. **在线命令用 `--version` 写死版本；离线命令用包路径**，任何位置不出现 `latest`。
4. **Operator 默认开启**：`operator.enabled: true` 必须配 `userToken`；关闭时写 `enabled: false`。Chart 默认 `true` 且 Token 必填，漏写会安装失败。
5. **采集模式必须可多选**，单选会丢一半能力。
6. **离线才写 image**，在线写了会把用户绑死到假地址。
7. **节点镜像与集群镜像 tag 不同**，离线覆盖时不要复制粘贴同一个。
8. **校验项只写结果**（`target_up=2`、指标有数据），不写"请检查版本"这类动作。
9. 左栏文案：**标题 ≤ 10 字 + 一行副标题（≤ 14 字）**。句式统一：采集目标用「采集 XXX」，采集方式用「按 XXX 发现 / 采集」，其余用名词式；超过这个长度的一律进 `?` 悬浮说明，不铺在页面上。
10. `?` 说明写三段：是什么、为什么开、开了的代价；单条 ≤ 90 字。tooltip 用 CSS 实现且 `pointer-events:none`，不能挡住开关点击。

---

## 9. 验收标准

| 检查 | 期望 |
|---|---|
| 默认态 | 在线；DaemonSet 与 StatefulSet 都选中；Operator 开；values 无 `image`；命令为 `oci://… --version 0.2.3` |
| 默认态主按钮 | **禁用**（Operator 的 Token 未填） |
| 切离线 | 出现 Chart 包地址与镜像仓库前缀；values 出现 3 处 `image`（视模式）；命令变为包路径 |
| 离线 + 仅 STS | `image` 覆盖 `categraf_ent:v0.5.45` 与 `kube-state-metrics/kube-state-metrics:v2.19.1`，无节点镜像 |
| 小节编号 | 在线 1 环境要求 / 2 准备配置 / 3 部署检查；离线 1 环境要求 / 2 同步物料 / 3 准备配置 / 4 部署检查 |
| 离线镜像同步条数 | 仅 DS = 1 条（+operator）；仅 STS = 2 条（+operator）；两者 = 3~4 条 |
| 切换同步工具 | 点 `docker tag / push` 后命令整体变成 pull/tag/push 三件套，条数与镜像数一致 |
| 离线 + 两者 | 3 处 `image` 全出现，节点/集群 tag 分别为 `servicemap-v0.5.45` / `v0.5.45` |
| 在线 + 两者 | 无 `image`；命令仍为 OCI + `--version` |
| 清空 Chart 包地址（离线） | 主按钮禁用 |
| 改集群名 | `clusterName` 与校验项 `cluster="…"` 同步 |
| 改命名空间 | 命令里所有 `-n` 同步 |
| 步骤 2 | 校验项随模式变化，标题编号与步骤一致 |
| 步骤 3 | 在线用 OCI + `--version 0.2.3`、离线用包路径；只勾 DS 时只输出 ds 的 rollout；页脚「完成」为禁用态 |
| 复制 | 三种模式 × 两种部署方式，复制内容都无模板残留、可直接执行 |
| 下载 values.yaml | 点「↓ 下载」得到 `values.yaml`，内容与右侧一致；改名或改参数后重新下载内容同步 |
| 必填标记 | 集群名称 / 命名空间 / 上报地址 带红色 `*`；关闭 Operator 后 API Token 不标红且不参与校验；离线时两个物料字段才标红 |
| 可选配置默认态 | 徽标「默认」；values 无 `customLabels` |
| 开「安装 Operator」但 Token 留空 | 主按钮禁用（避免装了跑不起来） |
| 开「自定义标签」并填 key | values 出现 `customLabels`，缩进在 `categraf:` 下 |
| STS 下关「安装 kube-state-metrics」 | `kubeStateMetrics.enabled: false`，其余不变 |
| STS 下网络插件选 Calico | `calico: true`、`cilium: false`；选「不采集」时两者都 `false` |
| 仅 DS 模式 | 可选配置里看不到 KSM / appMetrics / CoreDNS / 网络插件；也看不到远程写认证 |
| 仅 STS 模式 | 看不到主机三类、合规模式、上报标识 |
| 开「合规模式」 | `privileged: false` **且** `hostExec.enabled: false`（缺一不生效） |
| 填自定义采集任务 | 文本按 4 空格缩进写入 `extraScrapeConfigs`；appMetrics 自动置 `true` |
| 填业务组 / 远程写密码 | 分别出现 `heartbeatGid`、`remoteWriteUser/Password` |
| 默认在线 | values 里没有任何 `image:`（全部沿用 Chart 默认） |
| 在线改 Categraf 版本为 0.5.44 | 出现 `registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.44` 与 `:v0.5.44` |
| 离线改版本 | 同步镜像命令与 values 使用同一个新 tag |
| 版本留空 | 主按钮禁用 |
| 关闭 kube-state-metrics | KSM 版本输入框隐藏且不参与校验 |
| 资源规格选「小」 | 出现 `cpu: 100m` / `memory: 256Mi`；选「中·推荐」时整段不出现 |
| 资源规格选「自定义」 | 按模式显示分组：仅 DS 显示节点组、仅 STS 显示集群组、两者都显示；留空则主按钮禁用 |
| 自定义 + 仅 STS | 出现两组：`ksmCategraf.resources`（默认 500m/512Mi → 1000m/1.5Gi）与 `kubeStateMetrics.resources`（200m/256Mi → 500m/1Gi） |
| 小/大档位 | 三处 `resources` 同时写出：node / ksm agent / kube-state-metrics |
| 中档 | 只出现 `ksmCategraf.resources.limits.memory: 2Gi`，渲染后 cpu/requests 仍为 Chart 默认 |
| 关掉「安装 kube-state-metrics」 | `kubeStateMetrics.resources` 不再写，自定义里也不显示该分组 |
