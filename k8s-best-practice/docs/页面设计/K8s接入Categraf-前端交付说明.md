# K8s 接入 Categraf · 前端开发说明

> 对应 Demo：[`K8s接入Categraf-页面demo.html`](./K8s接入Categraf-页面demo.html)（单文件、零依赖，浏览器直接打开）
> Chart 基线 `0.2.3`｜appVersion `0.5.45`
> Demo 里的 values、命令、资源名都来自真实渲染，可直接当契约用。

---

## 1. 一句话描述

一个配置页：**左边填参数 → 右边实时生成 values.yaml 和命令**。不写文档、不做引导，用户只做三件事：填参数、复制配置、复制命令。

---

## 2. 页面结构

```
┌ 接入对象 ────────────────────────────────────────────┐
│ [Categraf ✓]        [应用性能分析接入 · 即将支持]      │
└──────────────────────────────────────────────────────┘
┌ ① 安装与配置 ┬ ② 接入校验 ┬ ③ 升级与卸载 ────────────┐
│                                                      │
│ 左：参数面板（330px）    右：内容（随 Tab 切换）        │
│  部署环境 / 部署方式      ① 环境要求（固定 3 条）       │
│  集群名称 / 命名空间      ② 同步物料（仅离线）          │
│  环境 / 业务组 ID         ③ 准备配置（values.yaml）     │
│  采集模式（多选）         ④ 部署并检查（命令）          │
│  安装 Operator + Token   ⑤ 接入校验 / 升级卸载          │
│  上报地址 / 采集间隔      每个代码块右上角：复制 / 下载   │
│  ▸ 可选配置（折叠）                                   │
│                                                      │
│ 底栏：上一步 / 下一步（最后一页「完成」置灰）           │
└──────────────────────────────────────────────────────┘
```

---

## 3. 状态模型

页面只有一个状态对象，任何输入变化 → `render()` 全量重绘右侧。

```js
{
  online: true,              // 在线/离线
  syncTool: "docker",        // 离线物料：docker | skopeo
  chartPath: "./categraf-0.2.3.tgz",
  regPrefix: "harbor.internal/flashcat",
  cluster: "prod-k8s-01",
  ns: "flashcat",
  envMode: "prod", envCustom: "",   // 选「自定义…」时用 envCustom 的值
  gid: "",
  addr: "http://flashcat.internal:19000",
  interval: "15",
  opToken: "",
  imgVer: "0.5.45", ksmVer: "2.19.1", opVer: "0.0.7",
  ds: true, sts: true,        // 采集模式（多选，至少一个）
  step: 1,
  opt: { /* 见 3.2 */ },
  res: "m",                   // s | m | l | custom
  reqCpu: "200m", reqMem: "512Mi", limCpu: "2000m", limMem: "2Gi",
  ksmReqCpu: "500m", ksmReqMem: "512Mi", ksmLimCpu: "1000m", ksmLimMem: "2Gi",
  ksReqCpu: "200m", ksReqMem: "256Mi", ksLimCpu: "500m", ksLimMem: "1Gi",
  extraJobs: ""               // 自定义 scrape_config 原文
}
```

### 3.1 主表单字段

| 字段 | 控件 | 默认 | 必填 | 落到 values |
|---|---|---|---|---|
| cluster | input | `prod-k8s-01` | ✅ | `categraf.clusterName` |
| ns | input | `flashcat` | ✅ | `helm -n` / `kubectl -n` |
| addr | input + 清空 | `http://flashcat.internal:19000` | ✅ | `categraf.serverAddr` |
| gid | input | 空 | — | `categraf.heartbeatGid` |
| envMode / envCustom | select + input | `prod` | 选「自定义…」时输入框必填 | `categraf.env` |
| opToken | input | 空 | Operator 开启时 ✅ | `operator.userToken` |
| interval | select | `15` | — | `categraf.config.interval` |
| ds / sts | 两张卡多选 | **都选中** | 至少一个 | `nodeCategraf.enabled` / `ksmCategraf.enabled` |

必填项在 label 后加红色 `*`；顶部有一行图例。离线时 `chartPath`、`regPrefix` 也标红并参与校验。

### 3.2 可选配置（折叠，按模式过滤显示）

| key | 标题 | 默认 | 出现条件 | values |
|---|---|---|---|---|
| ksm | 采集 K8s 对象状态 | 开 | 有 sts | `kubeStateMetrics.enabled` |
| appMetrics | 采集应用指标 | 开 | 有 sts | `appMetrics.enabled` |
| defaultJob | 按注解自动发现 | 开 | sts 且 appMetrics | `appMetrics.defaultJob.enabled` |
| extraJobs | 按自定义规则采集 | 关 | 有 sts | 文本 → `appMetrics.extraScrapeConfigs` |
| hostNative | 采集Categraf原生主机指标 | 开 | 有 ds | `nodeCategraf.inputs.hostNative.enabled` |
| cadvisor | 采集容器指标 | 开 | 有 ds | `nodeCategraf.inputs.cadvisor` |
| kubeProxy | 采集 Kube-proxy 指标 | 开 | 有 ds | `kubeProxy.enabled` |
| coreDns | 采集 CoreDNS 指标 | 开 | 有 sts | `coreDns.enabled` |
| networkPlugin | 采集网络插件指标 | 不采集 | 有 sts | `networkPlugin.calico/cilium.enabled` |
| controlPlane | 采集控制平面指标 | 关 | 有 sts | `controlPlane.enabled` |
| labels | 设备自定义标签 | 关 | 全部 | `categraf.customLabels`（key/value 多行） |
| ident | 设备标识 | 节点名 | 有 ds | `nodeCategraf.hostname` |
| remoteWrite | 写入认证 | user001 / 空 | 有 sts | `categraf.remoteWriteUser/Password` |
| imgVer / ksmVer / opVer | 镜像版本 | 0.5.45 / 2.19.1 / 0.0.7 | 对应组件启用时 | `*.image` |
| res | 资源规格 | 中 | 全部 | 见 4.3；作用对象是三个容器，选项里的数字只代表 requests |
| batch | 写入批量 | 默认 | 全部 | `categraf.writer.batch` |
| split | 指标抓取间隔 | 关 | 有 sts | `categraf.prometheus.scrapeInterval` |
| compliant | 非特权模式 | 关 | 有 ds | `securityContext.privileged: false` + `hostExec.enabled: false` |

---

## 4. 渲染规则（最容易写错的部分）

### 4.1 values.yaml 生成顺序

```
categraf:  serverAddr / clusterName / env [/ heartbeatGid] / config.interval
           [/ customLabels] [/ remoteWrite*] [/ writer.batch] [/ prometheus.scrapeInterval]
operator:  enabled + [/ userToken + image + cleanup]
nodeCategraf: enabled + [/ image] + [hostname] [/ securityContext + hostExec] + [inputs]
ksmCategraf:  enabled + [replicas] + [/ image] + [resources]
kubeStateMetrics: enabled + [/ image] + [resources]
appMetrics: enabled + [defaultJob.enabled] + [extraScrapeConfigs]
coreDns / networkPlugin / controlPlane: enabled（有 sts 时始终显式写）
kubeProxy: enabled（有 ds 时写）
```

### 4.2 四条硬规则

1. **`operator.enabled` 必须显式写**。Chart 默认 `true` 且 `userToken` 必填，漏写会安装失败。页面默认开、Token 必填（未填则主按钮禁用）。
2. **`appMetrics` / `kubeStateMetrics` 关掉时要显式写 `false`**，否则 Chart 默认值会回填。
3. **在线默认版本不写 image**，改了版本才写公网地址——否则会盖住 Chart 默认值，Chart 升级用户还钉在旧版本。离线模式则始终写。
4. **合规模式要同时关 `hostExec`**，只改 `privileged` 不生效（模板里 `hostExec.enabled: true` 会强制改回 `privileged: true`）。

### 4.3 资源规格

| 档位 | 节点 | 集群 | KSM |
|---|---|---|---|
| 小 | 100m/256Mi → 500m/1Gi | 200m/256Mi → 500m/1Gi | 100m/128Mi → 500m/1Gi |
| 中 | 不写，用 Chart 默认 | 不写 | 不写 |
| 大 | 500m/1Gi → 3000m/4Gi | 1000m/2Gi → 2000m/3Gi | 500m/1Gi → 1000m/2Gi |
| 自定义 | 三组输入框，按启用模式显示 | | |

> 中档不写任何 `resources`，全部沿用 Chart 默认值（0.2.3 起 KSM Agent 默认上限已是 2Gi）。

### 4.4 命令生成

| 场景 | 命令来源 |
|---|---|
| 在线安装 | `helm upgrade --install categraf oci://.../categraf --version 0.2.3 -n <ns> -f values.yaml` |
| 离线安装 | `helm upgrade --install categraf <chartPath> -n <ns> -f values.yaml` |
| 滚动检查 | 按模式拼 `rollout status ds/categraf`、`rollout status sts/categraf-ksm` |
| 升级 | 备份 values → upgrade → rollout → rollback |
| 卸载 | `uninstall --wait`（清设备）/ `--no-hooks`（保留）/ 关 cleanup 再升级 |

### 4.5 自定义抓取规则要能容错

用户很可能把整段 `appMetrics:` 粘进来。处理逻辑：

1. 找 `extraScrapeConfigs:` 行，只取其后内容
2. 计算非空行最小缩进并整体去掉
3. 去首尾空行
4. 结果仍不以 `-` 开头 → 黄色警示（不阻断）

否则 `extraScrapeConfigs` 会变成 map，Chart 报 `must be a list`。

---

## 5. 交互

| 项 | 规则 |
|---|---|
| 参数变化 | `input`/`change` 立即重绘右侧，无保存按钮 |
| 采集模式 | 多选，至少保留一个；取消最后一个时忽略点击 |
| 必填缺失 | 主按钮禁用 |
| 复制 | 复制 `<pre>` 文本，成功后按钮变「已复制」1.2s |
| 下载 | 仅 values 块有，文件名固定 `values.yaml`，内容取当前渲染 |
| `?` 说明 | CSS tooltip，`pointer-events:none` 不挡点击，图标下方展开 |
| URL 参数 | `?deploy=online\|offline`、`?mode=ds\|sts\|both`、`?step=1\|2\|3` |
| 步骤 | 1→2→3 顺序推进，最后一页「完成」置灰 |

---

## 6. 代码地图（Demo 单文件内）

| 函数 | 职责 |
|---|---|
| `render()` | 总入口：切 Tab、拼右侧 HTML |
| `valuesYaml()` | 生成 values，含所有条件分支 |
| `cmdText()` | 安装命令 |
| `upgradeCmd()` / `uninstallCmd()` | 第三页命令 |
| `envCheckCmd()` | 首节环境检查命令 |
| `chartSyncCmd()` / `imageSyncCmd()` / `imagePairs()` | 离线物料命令 |
| `normalizeJobs()` | 自定义规则粘贴容错 |
| `syncAdv()` | 可选配置的显隐、开关态、徽标计数 |
| `codeBlock()` / `hlYaml()` / `hlShell()` | 代码块与高亮 |
| 事件委托 | 复制、下载、同步工具切换、KV 增删、步骤与模式切换 |

样式全部内联在 `<style>`，可直接取用；无外部依赖。

---

## 7. 与后端对接

| 能力 | 现状 | 需要后端 |
|---|---|---|
| 业务组下拉 | Demo 为输入框 | 业务组列表接口 |
| 集群名查重 | 前端仅做非空校验 | 集群名唯一性检查接口 |
| 版本下拉 | Demo 为输入框 | 版本列表接口（可选） |
| values 落库 / 一键下发 | 未做 | 暂不需要 |

---

## 8. 验收清单

1. 默认：在线、两张采集卡都选中、Operator 开、主按钮禁用（Token 未填）
2. 填 Token 后主按钮可用；清空上报地址后再次禁用
3. 在线默认 values 里**没有任何 `image:`**
4. 在线把 Categraf 版本改成 0.5.44 → 出现 `registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.44`
5. 切离线 → 出现两个物料字段、values 全部带前缀、同步镜像条数与所选模式一致
6. 只勾 DaemonSet → values 里 KSM 相关全部 `false`，命令只有 ds 的 rollout
7. 开启「按自定义规则采集」并粘贴整段 `appMetrics:` → values 里是合法 list
8. 第三页：在线用 OCI + `--version 0.2.3`、离线用包路径；卸载块含 `--no-hooks`
