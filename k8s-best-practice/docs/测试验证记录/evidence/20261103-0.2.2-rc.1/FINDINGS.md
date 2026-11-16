# 0.2.2-rc.1 完整回归：发现的问题与待办

回归时间：2026-11-03 13:04–14:00（Asia/Shanghai）
被测包：`categraf-0.2.2-rc.1.tgz`，SHA256 `88d9449a…35a238a3a`
环境：K8s v1.28.2（k8s-node1/node2），Flashcat `http://flashcat.local:19000`，Helm 3.21.3 / 4.2.3

---

## F1（高，Chart 缺陷 — ✅ 已在 0.2.2-rc.2 修复）升级只改模板时配置不生效

**现象**：`helm upgrade` 0.2.1 → 0.2.2-rc.1（values 不变）后，Release 显示 deployed/rev2、Pod 全 Ready，但：

- Node Agent 实际挂载的 `config.toml` 仍是 0.2.1 版本（无 `customLabels` 的 owner/environment）；
- KSM Agent 仍用旧 scrape 配置 → `up{job="app-metrics"}` 缺失；
- 指标里查不到 `owner="platform"` 标签。

**证据**：
- [25-upgrade-config-staleness.md](25-upgrade-config-staleness.md) A 节：ConfigMap 有新内容，Pod 内 `/opt/categraf/conf/config.toml` 无新内容；Pod `creationTimestamp` 仍是安装 0.2.1 的时刻（升级未触发滚动）。
- [25-upgrade-config-staleness.md](25-upgrade-config-staleness.md) C 节：`kubectl rollout restart ds/sts` 后同一 Pod 内配置变为新内容，`count({owner="platform"})` 从 0 → 13326，`up{job="app-metrics"}` 从 missing → 1。

**根因（已用渲染对比精确复现，见 [26-F1-rootcause.md](26-F1-rootcause.md)）**：`templates/_helpers.tpl` 的 `categraf.valuesChecksum` 只对 `.Values` 做哈希（不是对“最终渲染出来的配置”做哈希）：

```
{{- define "categraf.valuesChecksum" -}}{{- .Values | toYaml -}}{{- end -}}
```

本次升级用的是同一份 `/root/categraf-024-regression-values.yaml`：rc.1 新增的那些默认值（`customLabels`、`config.interval`、`writer.*`、`heartbeat.*`）全部被这份 values 覆盖，合并后的 `.Values` 与 0.2.1 时**完全相同**，于是 `checksum/config` 注解也完全相同。

用真实 values 渲染两份 Chart 的实测结果：

| Chart | Pod 模板 `checksum/config` 注解 |
|---|---|
| `0.2.1` | `2911955df9e08447e5583d463521688bf6bc74d6040b8c798ab041f9c38921e1` |
| `0.2.2-rc.1` | `2911955df9e08447e5583d463521688bf6bc74d6040b8c798ab041f9c38921e1`（**完全相同**） |
| `0.2.2-rc.1` + 改一个 values（env=prod） | `0a2ce0be…`（变了，会滚动） |

而两份 Chart 渲染出的配置内容确实不同（`config.toml` 多了 customLabels、`cluster-scrape.yaml` 修了 metrics_path/path relabel）——即“配置变了，但决定是否重启的指纹没变”。Pod 模板里除了这个注解没有其它随版本变化的字段，所以 Helm 认为无需滚动；配置又是 `subPath` 挂载（ConfigMap 更新不会反射进容器），Agent 进程继续用旧文件 → 新功能静默不生效。

**影响**：任何“只改模板、不改 values”的升级都会出现“升级成功但功能没上线”。对本次 0.2.1→0.2.2 升级是致命误导。

**修复状态：已在 `0.2.2-rc.2` 按方案 1 修复并验证** —— 新增 `templates/_config.tpl`（`nodeConfigToml` / `ksmConfigToml` / `ksmScrapeYaml` 命名模板，ConfigMap 与 checksum 共用同一来源），`checksum/config` 改为 `sha256(Chart.Version + .Values + 三段渲染后的配置)`；4 个 workload 注解统一改用它。

- 等价性证据：[28-F1-fix.md](28-F1-fix.md)（与 rc.1 渲染逐字节一致，仅 checksum 注解变化；checksum 语义验证：values 变→变、配置正文变→变、加注释的无害改动→不变、版本号变→变）
- 端到端证据：[29-F1-fix-verified.md](29-F1-fix-verified.md)（独立 namespace 用同一份 values 从 0.2.1 升级 rc.2：Pod 自动滚动、Pod 内配置立即更新、customLabels 指标与设备标签出现，无需人工 `rollout restart`）

**原始修复建议（留档）**：
1. checksum 改成哈希**渲染后的配置内容**：把 node 的 `config.toml`、ksm 的 `config.toml` + `cluster-scrape.yaml` 抽成命名模板，再对渲染结果做 sha256sum。这样“模板/配置变化必然触发滚动”，是根治方案；
2. 最小改动版：把 Chart 版本放进 checksum，例如
   `checksum/config: {{ printf "%s:%s" .Chart.Version (.Values | toYaml) | sha256sum }}`
   （一行改动即可覆盖“版本升级导致模板变化”的场景；缺点是同版本重建不覆盖，内部测试包可能遇到）；
3. 保留 subPath 但文档强制要求升级后 `kubectl rollout restart`（最差方案）。

**当前规避**：升级后执行
`kubectl -n categraf rollout restart ds/categraf && kubectl -n categraf rollout restart sts/categraf-ksm`

---

## F2（低，已知问题延续）syslog collector 仍在报错

**现象**：Chart 已用空 ConfigMap 覆盖 `/opt/categraf/conf/input.syslog` 目录（`categraf-disable-syslog`），但 Node Agent 仍持续输出：

```
collector failed name syslog ... err failed to execute tail command: exit status 1
failed to collect from log file ... failed to execute tail command: exit status 1
```

**证据**：
- [25-upgrade-config-staleness.md](25-upgrade-config-staleness.md) B/D 节：Pod 内 `/opt/categraf/conf/input.syslog` 为空目录（挂载生效），`/usr/bin/tail` 存在，`grep -rl syslog /opt/categraf/conf` 无结果；
- [22-logs.txt](22-logs.txt)：当前容器最近 300 行仍命中 10 条 `tail command` 报错。

**判断**：本地 conf 已无 syslog 配置却仍有采集器在跑，说明配置来自 `providers = ["local","http","rmq"]` 的远程下发（Flashcat 数据集成下发的 syslog 采集任务）或镜像内置默认；报错原因是采集目标文件在该容器视角不存在。**不是本次 Chart 模板改动能关闭的**。

**建议**：单独处理——在 Flashcat 侧确认是否有远程下发的 syslog 采集任务；或在 Chart 中增加显式的 `input.syslog` 关闭开关（如启用时删除该 input 目录之外再考虑 `--disable-inputs`）。当前非阻塞，不影响指标与上报。

---

## F3（文档）外部 test-env skill 的 cleanup 默认值与 Chart 不一致

- skill 文档（`~/.codex/skills/test-env/SKILL.md:58` 与 `~/.agents/...` 同文）写“cleanup 默认 false，仅在用户明确要求时开启”；
- Chart `values.yaml` 实际默认 `operator.cleanup.nodeCategraf/ksmCategraf: true`；
- 本次实测（见 [10-lifecycle.md](10-lifecycle.md)）：`helm uninstall` 时 pre-delete hook 主动删除了 3 个设备（2 node + 1 ksm），证明默认开启。

**建议**：修正共享环境文档/skill 描述（属于仓库外文件，本次未改，等确认）。

## F4（文档）Chart README 的“已验证范围”需按本次回归更新

现写“实际集群安装、卸载和重新上报在 Kubernetes 1.28.2 验证”。本次另外验证了：0.2.1→rc.1 真实升级、`helm rollback`、卸载清理 Hook、重装、多 Release 隔离、多开关组合、自愈。建议补充，并保留“1.32+ 仅模板渲染、未在真实集群安装”的说明。已在 G8 阶段更新。

---

## 附带确认的无缺陷项（避免误报）

- 0.2.1 不支持 `customLabels` / 结构化运行时参数：值被忽略且不报错，渲染 interval=15、batch=2000，设备 tags 无 owner/environment —— 与“0.2.2 起支持”的文档一致（证据：[10-lifecycle.md](10-lifecycle.md) 2.1 节）。
- 升级后设备 tags 会在 Pod 重启并重新心跳后更新（无需删除设备）（证据：[25-upgrade-config-staleness.md](25-upgrade-config-staleness.md) C 节后的 API 查询）。
- `helm uninstall` 的 cleanup hook 正常：删除 3 个设备、delete_errors=0、不影响其它集群的 3 个设备（证据：[10-lifecycle.md](10-lifecycle.md) 1 节）。

## F5（中，Chart 缺陷 — ✅ 已在 0.2.2-rc.3 修复）`controlPlane.enabled=true` 时 apiserver 永远采不到

**现象**：开启 `controlPlane.enabled=true` 后，`apiserver` job 已渲染进 `cluster-scrape.yaml`，但从未产生 `up{job="apiserver"}` 序列（不是 up=0，而是根本没有 target），apiserver 指标不可用。

**证据**：
- 静态对比 [33-controlplane-apiserver.md](33-controlplane-apiserver.md) A 节：同一模板内
  - `kube-state-metrics` job（第 62 行）与 `coredns` job（第 182 行）用的是 `__meta_kubernetes_endpoint_port_name`（正确，实测 up=1）；
  - `apiserver` job（第 125 行）用的是 `__meta_kubernetes_port_name`（endpoints 角色不存在该标签）。
- 运行态：`count(count_over_time(up{job="apiserver"}[10m])) = 0`（B/C 节）。
- 开关组合实测：`C6f-apiserver up=1` 期望 1、实际 0（[32-features-fix.md](32-features-fix.md)）。

**根因**：`templates/ksm-categraf.yaml:125` 的 keep 过滤器把 `__meta_kubernetes_port_name` 当作端点端口名；该元标签在 `role: endpoints` 下不存在，导致 `regex: default;kubernetes;https` 永远匹配不到，目标被全部丢弃。

**修复建议**：把第 125 行改为
```yaml
source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
```
与同文件其它 endpoints job 保持一致；改完在测试集群上确认 `up{job="apiserver"}=1`（需 KSM Agent 重启加载配置）。

**修复状态：已在 `0.2.2-rc.3` 修复并验证** —— `templates/_config.tpl` 中 apiserver job 的 keep 过滤器改为 `__meta_kubernetes_endpoint_port_name`（与同文件 kube-state-metrics / coredns 两个 job 一致）。

- 改动证据：[30-F5-fix.md](30-F5-fix.md)（开启 controlPlane 时 rc.3 vs rc.2 渲染只差这一行；关闭时零差异）
- 端到端证据：[31-F5-verified.md](31-F5-verified.md)（独立 namespace 装 rc.3 + controlPlane：`up{job="apiserver"}=1`；controller-manager/scheduler/etcd 为 `up=0`，目标已正确发现、仅被 master 的 127.0.0.1 监听拒绝 → 环境限制）

**影响（修复前）**：`controlPlane.enabled`（默认 false）开启后 apiserver 指标缺失；controller-manager / scheduler / etcd 在本测试集群因 master `--bind-address=127.0.0.1` 本来也采不到（环境限制，需按文档放开监听），修好 apiserver 后该开关至少有一项可用。

---

## 测试方法造成的“假 FAIL”（已核实，非缺陷）

首轮 G4 有几条断言失败是取数方法问题，修正轮已用“短窗口 + 全量 target”重测通过：

| 首轮 FAIL | 真实原因 | 修正后证据 |
|---|---|---|
| C5-cadvisor/nodeExporter/hostNative.disk 关闭后指标“仍在” | 用 90s `count_over_time` 窗口，旧样本仍在窗口内 | 60s 短窗口 + 130s 观察后为 0（[32-features-fix.md](32-features-fix.md) C5f） |
| C7-KSM target“仍 up=1” | VictoriaMetrics instant 查询 5 分钟 lookback 返回旧样本 | 60s 短窗口判定为 0（C7f） |
| C4-改坏 path 后 target“仍 up=1” | 滚动期间新旧 target 并存，脚本只取了 `.data.result[0]` | 单独复测：改坏后 `up=0`，恢复后 `up=1`，说明 annotation path 覆盖**有效**（[34-path-override.md](34-path-override.md)） |
| `C7f-kube_pod_info 停止上报` | 测试 Pod `annotated-metrics-test` 本身用 KSM 镜像，自带 kube_* 指标经 app-metrics job 上报；原断言未按 job 过滤 | 已关闭：`kube_pod_info{job="kube-state-metrics"}` 在 KSM 关闭 120s 后为 0（[32-C7f-recheck.md](32-C7f-recheck.md)） |
| C9-rg 设备数“空”/清理“空” | 设备注册等待 50s 偏短 + jq 取值路径不够健壮 | 90s 等待 + 健壮 jq 后 3/3、卸载后 0（C9 重测） |

## 补充：另外两条“假 FAIL”的处置（本轮最终核实）

- **多 Release 首轮卸载清理 FAIL**（`C9-rg 卸载后本集群清理`、`G10-rg 卸载后本集群设备清理`）：首轮因重复执行/中断导致 Helm release 状态异常，`helm uninstall` 报 `uninstall: Failed to purge the release: release: not found`，pre-delete Hook 未执行，设备残留。**干净重来**后（见 [36-multi-release-final.md](36-multi-release-final.md) G10b）Hook 正常删除第二个 Release 的 3 台设备、主集群 3 台不受影响，判定为非缺陷。残留的 3 台 `…-rg` 设备也已在本次干净卸载中一并清掉。
- **AUDIT-A13 FAIL**：审计脚本 `g8a.sh` 里 A13 的命令写法（`grep -q ... && echo OK`）导致返回值不稳定，改为直接比对 `serverVersion.gitVersion` 后 13/13 通过；与 Chart 无关。
