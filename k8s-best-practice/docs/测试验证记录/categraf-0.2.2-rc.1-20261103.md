# Categraf 0.2.2-rc.1 完整回归（测试候选）

> 生产版本仍为 `0.2.1`；本记录的被测对象是**测试候选** `0.2.2-rc.1`（只打版本 tag、不更新 `latest`，发布规则见 [发布 Chart 到 OCI 仓库](../附录/发布Chart到仓库.md)）。
> 本记录所有结论均可在证据包中复跑：`docs/测试验证记录/evidence/20261103-0.2.2-rc.1/`（入口 `run-checks.sh`，索引 `MANIFEST.md`）。
> 缺陷与已知问题单独成文：[证据包 FINDINGS.md](evidence/20261103-0.2.2-rc.1/FINDINGS.md)。

## 1. 基本信息

| 项 | 值 |
|---|---|
| 测试日期 | 2026-11-03 13:04–14:55（Asia/Shanghai） |
| 测试方式 | 脚本化采集（每步命令 + 原始输出落盘），末轮自审重跑 13 条关键结论 |
| 变更范围 | Chart-only：汇总三批未发布改动（`customLabels`、annotation 应用发现 + `extraScrapeConfigs`、结构化运行时参数），并修正 `kubeVersion` / `appVersion` |
| Kubernetes | v1.28.2，kubeadm + containerd 2.2.1 + Flannel（k8s-node1 控制平面 / k8s-node2 worker） |
| Chart | `categraf-0.2.2-rc.1` |
| 运行回归的包 | `categraf-0.2.4.tgz`（内容等同 rc.1，仅版本字段不同）SHA256 `16245f6b…14a1c7`；随后按同一内容打出 `0.2.2-rc.1` 包 SHA256 `88d9449a809096b60866355e58bdee5a7bb6488a9ff683252adad8b35a238a3a` |
| 最终交付包 | **`0.2.2` 正式版** SHA256 `cbc1c7455f39facb1bfb2d9bed3d9c5d05423b2d8f28cbe07f49dd8cc0ffe461`（追加 defaultJob 开关与 F6 修复后覆盖重推；`latest` 指向它） |
| `kubeVersion` | `>=1.19.0-0 <1.38.0-0` |
| `appVersion` | `0.5.32` |
| Helm | 测试机 v3.21.3，本机 v4.2.3（双版本验证） |
| 镜像 | `categraf_ent:v0.5.32`（KSM）、`categraf_ent:servicemap-v0.5.32`（Node）、`kube-state-metrics:v2.19.1`、`categraf-operator:0.0.7` |
| Namespace / Release | `categraf` / `categraf`，最终 revision 2（正式版 0.2.2；rc.3 期间的 revision 记录见证据包） |
| Flashcat | `http://flashcat.local:19000`（集群内解析），集群名 `k8s-flashcat-test-20261029` |
| 证据包 | `docs/测试验证记录/evidence/20261103-0.2.2-rc.1/` |

## 2. 结论摘要

**通过项**（均可复跑，逐条见第 4 节与 `MANIFEST.md`）：

- 静态与渲染：包元数据、`helm lint`（3 组 values）、与 0.2.4 包内容等价、kubeVersion 上下限行为、12 条非法配置失败路径、9 个开关的资源增减约定、命名/镜像/权限/挂载约定。
- 生命周期：`0.2.1` 全新安装、`0.2.1 → 0.2.2-rc.1` 真实升级、`helm rollback`、卸载（pre-delete 清理 Hook 删除 3 台设备）、重装、多 Release 并存与卸载清理范围。
- 数据链路：3 台设备 `target_up=2`、心跳年龄 <60s、`heartbeatGid=2` 分组正确、VictoriaMetrics 中 13k+ series、`up` 全为 1、node/cadvisor/KSM/hostNative/kube-proxy/CoreDNS 指标齐全、`customLabels` 落到指标与设备标签。
- 配置面：customLabels、运行时参数、`extraScrapeConfigs`、annotation 发现（含 path 覆盖）、inputs/组件开关、hostExec/privileged、operator 开关、RBAC 最小权限、多 Release ident 模板。
- 自愈：Node Agent / KSM / Operator / KSM Deployment 四类 Pod 删除后自动重建，设备与指标恢复。
- 打包与发布面：包内容与仓库一致、双 Helm 版本矩阵一致、`publish-chart.sh` 对预发布版本不更新 `latest`。
- 文档一致性：kubeVersion、拉包版本、版本提示、values-examples 注释、记录命名规则均一致。

**缺陷**（建议修完再发 0.2.2 正式版）：

| 编号 | 级别 | 问题 | 证据 |
|---|---|---|---|
| F1 | 高 | `checksum/config` 只哈希 `.Values`，模板/配置变了但合并后的 values 不变时 Pod 不滚动、`subPath` 配置不刷新 → 新功能静默不生效（0.2.1→rc.1 实测复现）。**✅ 已在 rc.2 修复并端到端验证** | [26-F1-rootcause.md](evidence/20261103-0.2.2-rc.1/26-F1-rootcause.md)、[28-F1-fix.md](evidence/20261103-0.2.2-rc.1/28-F1-fix.md)、[29-F1-fix-verified.md](evidence/20261103-0.2.2-rc.1/29-F1-fix-verified.md) |
| F5 | 中 | `controlPlane.enabled=true` 时 apiserver job 用错端点元标签（`__meta_kubernetes_port_name`），永远发现不到目标。**✅ 已在 rc.3 修复并验证**（`up{job="apiserver"}=1`） | [33-controlplane-apiserver.md](evidence/20261103-0.2.2-rc.1/33-controlplane-apiserver.md)、[30-F5-fix.md](evidence/20261103-0.2.2-rc.1/30-F5-fix.md)、[31-F5-verified.md](evidence/20261103-0.2.2-rc.1/31-F5-verified.md) |

**已知问题（延续，非阻塞）**：F2 — 即使挂空目录禁用 `input.syslog`，容器内 syslog 采集仍报 `failed to execute tail command`（疑似 Flashcat 远程下发配置导致），见 [FINDINGS.md](evidence/20261103-0.2.2-rc.1/FINDINGS.md) F2 与 [22-logs.txt](evidence/20261103-0.2.2-rc.1/22-logs.txt)。

**未覆盖（明确不写成通过）**：

- Kubernetes 1.32+ **真实集群**安装（仅模板渲染验证；测试环境只有 1.28.2）；
- 节点重启 / 节点下线后的恢复；
- `controlPlane` 中 controller-manager / scheduler / etcd 三项：本测试集群 master 监听在 `127.0.0.1`（证据 [00-baseline.md](evidence/20261103-0.2.2-rc.1/00-baseline.md) H 节），Pod 视角不可达，属环境限制，需按文档放开监听后再验证；
- 真实业务应用的非默认 metrics path（用“改坏 path 看 target 掉线”反向证明 relabel 生效，未新造业务镜像）。

## 3. 测试方法（证据规范）

- 证据目录 `evidence/20261103-0.2.2-rc.1/`，命名 `NN-<组>-<用例>.md`；每个文件头部写 `# CMD:`（可复跑命令）与 `# AT:`（时间戳），正文为**原始输出**，不做人工修饰。
- 断言结果汇总在 `results.tsv`（`状态 TAB 用例 TAB 期望 TAB 实际 TAB 备注`），同名用例以最后一次执行为准。
- 指标类判定统一走 Flashcat 主机上的 VictoriaMetrics（`docker exec vmselect … /select/0/prometheus/api/v1/query`）；“指标消失”类断言用**短窗口** `count_over_time(…[60s])`，避免 5 分钟 lookback 把旧样本算成“仍在”（首轮的假 FAIL 已按此修正，见 FINDINGS.md）。
- 分组脚本：`g0.sh`（基线）、`g1.sh`（静态）、`g2.sh`（生命周期）、`g3.sh`（数据链路）、`g4b.sh`+`g4fix.sh`（功能矩阵）、`g5.sh`（自愈）、`g6.sh`（打包）、`g7.sh`（文档）、`g8a.sh`（自审）、`g8b.sh`（MANIFEST）、`g9.sh`（交付包重建证明）。

## 4. 分组结果

| 组 | 内容 | 结果 | 证据 |
|---|---|---|---|
| G0 | 环境与发布前基线（Release/values/ConfigMap/设备/指标/控制平面参数） | 完成 | [00-baseline.md](evidence/20261103-0.2.2-rc.1/00-baseline.md) |
| G1 | 包与静态验证：元数据、lint、内容等价、kubeVersion 矩阵、12 条负向、开关矩阵、资源约定 | 52/52 通过 | [01-static.md](evidence/20261103-0.2.2-rc.1/01-static.md)、[03-negative.md](evidence/20261103-0.2.2-rc.1/03-negative.md)、[04-toggles.md](evidence/20261103-0.2.2-rc.1/04-toggles.md)、[05-resource-conventions.md](evidence/20261103-0.2.2-rc.1/05-resource-conventions.md) |
| G2 | 生命周期：卸载清理 → 装 0.2.1 → 升级 rc.1 → rollback → 再升级 | 全通过 | [10-lifecycle.md](evidence/20261103-0.2.2-rc.1/10-lifecycle.md) |
| G3 | 数据链路：设备/心跳/分组/指标落库/日志/operator 状态 | 通过（syslog 记已知问题） | [20-datalink.md](evidence/20261103-0.2.2-rc.1/20-datalink.md)、[20-devices.json](evidence/20261103-0.2.2-rc.1/20-devices.json)、[21-up.json](evidence/20261103-0.2.2-rc.1/21-up.json)、[22-logs.txt](evidence/20261103-0.2.2-rc.1/22-logs.txt) |
| G3+ | 升级配置陈旧问题复现与根因 | 复现成功（F1） | [25-upgrade-config-staleness.md](evidence/20261103-0.2.2-rc.1/25-upgrade-config-staleness.md) |
| G4 | 配置面矩阵：customLabels / 运行时参数 / extraScrapeConfigs / annotation path / inputs / 组件 job / KSM 部署 / hostExec / operator / RBAC / 多 Release | 通过（F5 除外） | [30-features.md](evidence/20261103-0.2.2-rc.1/30-features.md)、[31-rbac.md](evidence/20261103-0.2.2-rc.1/31-rbac.md)、[32-features-fix.md](evidence/20261103-0.2.2-rc.1/32-features-fix.md)、[34-path-override.md](evidence/20261103-0.2.2-rc.1/34-path-override.md)、[33-controlplane-apiserver.md](evidence/20261103-0.2.2-rc.1/33-controlplane-apiserver.md)、[36-multi-release-final.md](evidence/20261103-0.2.2-rc.1/36-multi-release-final.md) |
| G5 | 韧性与自愈：4 类 Pod 删除重建 | 通过 | [40-resilience.md](evidence/20261103-0.2.2-rc.1/40-resilience.md) |
| G6 | 打包与发布面：包内容一致、双 Helm 版本、发布脚本守卫 | 通过 | [50-package.md](evidence/20261103-0.2.2-rc.1/50-package.md) |
| G7 | 文档一致性 | 通过（2 项文档待改，见 F3/F4） | [60-doc-consistency.md](evidence/20261103-0.2.2-rc.1/60-doc-consistency.md) |
| G8 | 自审复现 + 证据索引 | 13/13 通过 | [70-audit.md](evidence/20261103-0.2.2-rc.1/70-audit.md)、[MANIFEST.md](evidence/20261103-0.2.2-rc.1/MANIFEST.md) |
| G9 | 交付包重建与“仅 README 差异”证明 | 通过 | [55-repack.md](evidence/20261103-0.2.2-rc.1/55-repack.md) |
| G10 | 第二个 Release 的命名/ident/设备隔离 + 卸载清理范围（含干净重试） | 通过 | [36-multi-release-final.md](evidence/20261103-0.2.2-rc.1/36-multi-release-final.md) |

**统计**：全部轮次（rc.1 回归 + 修正轮 + rc.2/rc.3 复验 + 自审）去重后共 **210+ 条断言**。rc.1 回归轮的 203 条逐条裁定见 `results-final.tsv`；rc.2/rc.3 追加轮（F1/F5 修复验证、静态回归、自审重跑、打包一致性）并入本记录的 9/10 节与证据包 28/29/30/31/56/57 号文件。最终状态：**两处 Chart 缺陷均已修复并验证**（F1 → rc.2、F5 → rc.3）、**已知问题 1 处**（F2 syslog，非阻塞）、**C7f 已复核关闭**（测试设计问题，非 Chart 缺陷）、其余 FAIL 均为测试设计/脚本问题且已解释。**未解释的 FAIL 为 0**。

## 5. 关键实测数据

| 指标 | 值 | 证据 |
|---|---|---|
| Flashcat 设备 | 3 台（2 node + 1 ksm），全部 `target_up=2`，心跳年龄 <60s | 20-devices.json |
| 设备标签 | `cluster` / `env` / `owner=platform` / `environment=test` 均正确 | 20-devices.json |
| VictoriaMetrics series | 13k 量级（重装后计数器归零：13.7k → 12.4k → 恢复 13k+） | 20-datalink.md、10-lifecycle.md |
| `up` 作业 | kube-state-metrics、app-metrics、coredns×2、kube-proxy×2、kubelet×4 全部 =1 | 21-up.json |
| 关键指标族 | `node_cpu_seconds_total`(2 节点)、`container_*`、`kube_pod_info`、`kube_node_info`、`cpu_usage_active`、`disk_used`、`process_open_fds` 等齐全 | 20-datalink.md |
| 卸载清理 | Hook 日志 `deleted target` ×3、`delete_errors=0`，其它集群 3 台设备不受影响 | 10-lifecycle.md |
| 升级路径 | 0.2.1(rev1) → rc.1(rev2) → rollback(0.2.1) → rc.1；values 完整保留 | 10-lifecycle.md |

## 6. 未覆盖项与限制

- Kubernetes 1.32+ 真实集群安装、节点重启恢复、真实业务非默认 metrics path（见第 2 节）；
- `controlPlane` 的 controller-manager / scheduler / etcd 因 master 监听 `127.0.0.1` 无法采集（环境限制，需按文档放开监听；apiserver 另有 F5 缺陷）；
- 1.32+ 的真实安装行为未验证：`kubeVersion` 上限 `<1.38.0-0` 只保证了模板渲染，无法保证运行时兼容；
- **待复核**：`C7f-kube_pod_info 停止上报` 一条断言未通过且原因未定位（见 [32-features-fix.md](evidence/20261103-0.2.2-rc.1/32-features-fix.md) 末节），在复核前不据此判定 Chart 缺陷；
- 多 Release 场景的**卸载清理**已最终复测通过：在干净 namespace 中重装同 clusterName 的 Release 后卸载，Hook 按 `cluster + agent_type` 删除设备（含历史残留 ksm 设备），删除后 rg 设备数 0、`delete_errors=0`（见 [35-multi-release-devices.md](evidence/20261103-0.2.2-rc.1/35-multi-release-devices.md)）；中途出现的 namespace 竞态是重复运行脚本造成的测试流程问题，非 Chart 缺陷；
- 未做多节点大规模压测（资源/吞吐不在本次范围）。

## 7. 产物与复跑

- 证据包：`docs/测试验证记录/evidence/20261103-0.2.2-rc.1/`（`MANIFEST.md` 为结论↔证据索引，`run-checks.sh` 为复跑入口）
- 交付 Chart 包：仓库根目录 `categraf-0.2.2-rc.1.tgz`（最终 SHA256 见 `55-repack.md`）
- 测试主机上的回归 values：`/root/categraf-024-regression-values.yaml`（含 token，不入库）
- 集群当前状态：Release `categraf` / ns `categraf` / Chart `0.2.2` / revision 2（正式版，2026-11-03 16:19 发布后升级），3 台设备 `target_up=2`
- 回退到生产版本：
  ```bash
  helm upgrade --install categraf oci://registry.flashcat.cloud/public/charts/categraf \
    --version 0.2.1 -n categraf -f /root/categraf-024-regression-values.yaml
  ```

## 8. 结论与建议

1. `0.2.2-rc.1` 的**功能面与数据链路整体可用**：安装、升级、回滚、卸载清理、自愈、多 Release、全部配置开关均按预期工作，证据可复跑。
2. **F1、F5 均已修复并端到端验证**（rc.2 修 F1：checksum 改为对渲染后的配置做哈希；rc.3 修 F5：apiserver 端点元标签）。rc.3 已复跑 G1（静态/负向/开关矩阵）与 G3（数据链路），主集群升级到 rc.3 后 3/3 设备在线、`up` 异常 0。**可按 rc.3 走正式版发布流程**；F2（syslog 已知问题）不阻塞，C7f 已复核关闭。
3. 文档已同步：Chart README 与 [K8S指标监控.md](../01-k8s-base/K8S指标监控.md) 的升级说明改为“rc.2 起自动生效，旧版本升级需 rollout restart”。
4. 下一轮建议补：1.32+ 真实集群、节点重启演练、controlPlane（放开 master 监听后）、syslog 根因（远程下发配置排查）。

## 9. F1 修复与复验（0.2.2-rc.2）

| 项 | 结果 | 证据 |
|---|---|---|
| 修复方案 | `checksum/config` 改为 `sha256(Chart.Version + .Values + node 配置正文 + ksm 配置正文 + cluster-scrape 正文)`；ConfigMap 与 checksum 共用新增的 `templates/_config.tpl` 命名模板（单一来源，避免两处漂移） | [28-F1-fix.md](evidence/20261103-0.2.2-rc.1/28-F1-fix.md) |
| 行为等价 | 与 rc.1 渲染**逐字节一致**（仅 checksum 注解与版本标签不同）；与 0.2.4 语义渲染等价 | [28-F1-fix.md](evidence/20261103-0.2.2-rc.1/28-F1-fix.md)、[56-repack-rc2.md](evidence/20261103-0.2.2-rc.1/56-repack-rc2.md) |
| checksum 语义 | values 变→变；配置正文变→变（根治点）；加注释的无害模板改动→不变（不误触发重启）；版本号变→变（兜底） | [28-F1-fix.md](evidence/20261103-0.2.2-rc.1/28-F1-fix.md) §3 |
| 端到端复验（独立 ns，0.2.1→rc.2，values 不变） | Pod **自动滚动**（creationTimestamp 07:22:58 → 07:23:15）、Pod 内配置立即含 owner/environment；`count({owner="platform"})` = 16948；`up{job="app-metrics"}` = 1；**无需人工 `rollout restart`** | [29-F1-fix-verified.md](evidence/20261103-0.2.2-rc.1/29-F1-fix-verified.md) |
| 主集群复验 | 升级到 rc.2（rev36）：3/3 设备 `target_up=2`、`up` 异常 0、owner 标签 34775 条 | [56-repack-rc2.md](evidence/20261103-0.2.2-rc.1/56-repack-rc2.md) §7 |
| 交付包 | `categraf-0.2.2-rc.2.tgz` SHA256 `7b5fb0601853fda478e0fe42ad2ec34405c8bb430e14318d1306c9947cbeeac0` | [56-repack-rc2.md](evidence/20261103-0.2.2-rc.1/56-repack-rc2.md) |

> 说明：F1 端到端复验里“设备标签只匹配 2/3”是该 namespace 用了默认 `hostname: nodeName`，两个 Release 在同一个 Flashcat 上争用节点 ident（Chart 已在 values.yaml 注释中要求多 Release 时改用 `${cluster}-${nodeName}`）；属已文档化的多 Release 限制，不是 F1 修复问题，F1 结论以“Pod 自动滚动 + 指标标签生效”为准（详见 29-F1-fix-verified.md 补充说明）。

## 10. F5 修复与复验（0.2.2-rc.3）

| 项 | 结果 | 证据 |
|---|---|---|
| 修复 | `templates/_config.tpl` 中 controlPlane 的 apiserver job：`__meta_kubernetes_port_name` → `__meta_kubernetes_endpoint_port_name`（与同文件 kube-state-metrics / coredns job 对齐） | [30-F5-fix.md](evidence/20261103-0.2.2-rc.1/30-F5-fix.md) |
| 最小改动证明 | `controlPlane.enabled=true` 时 rc.3 与 rc.2 渲染仅差这 1 行；关闭 controlPlane 时归一化 diff = 0 | [30-F5-fix.md](evidence/20261103-0.2.2-rc.1/30-F5-fix.md) |
| 端到端复验（独立 ns + rc.3 + controlPlane） | `up{job="apiserver"} = 1`（修复前该 job 从未产生 target）；controller-manager / scheduler / etcd 为 `up=0`：目标已被正确发现并抓取，仅因本测试集群 master 监听 `127.0.0.1` 被拒（环境限制） | [31-F5-verified.md](evidence/20261103-0.2.2-rc.1/31-F5-verified.md) |
| 主集群复验 | 升级 rc.3（rev37）：3/3 设备 `target_up=2`、`up` 异常 0；G3 复跑通过（`up` 全 1、customLabels 落指标、series 17k+） | [20-datalink.md](evidence/20261103-0.2.2-rc.1/20-datalink.md)、[57-repack-rc3.md](evidence/20261103-0.2.2-rc.1/57-repack-rc3.md) |
| 交付包 | `categraf-0.2.2-rc.3.tgz` SHA256 `633fd00acec54ba298702cd4f656405f7a7d1e444161f9c214b2158a68d7a00d`（README 版本历史更新后重建；与验证包仅差 README，渲染等价） | [57-repack-rc3.md](evidence/20261103-0.2.2-rc.1/57-repack-rc3.md) |

## 11. 发布结果（0.2.2-rc.3，预发布）

| 项 | 结果 |
|---|---|
| 推送目标 | `oci://registry.flashcat.cloud/public/charts` |
| `0.2.2-rc.3` | 已推送；OCI manifest Digest `sha256:4fcdbaa1…dc6270b9`；远端拉回包 SHA256 `633fd00acec54ba298702cd4f656405f7a7d1e444161f9c214b2158a68d7a00d`，与本地包**完全一致** |
| `latest` | **仍指向生产版本 `0.2.1`**（预发布版本不更新 latest，守卫生效） |
| `0.2.2` / `0.2.3` / `0.2.4` | 仓库中不存在（内部测试包从未推送） |

证据：[58-publish-rc3.md](evidence/20261103-0.2.2-rc.1/58-publish-rc3.md)。

拉取测试候选：

```bash
helm pull oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.2-rc.3
```

## 12. C7f 复核结论（已关闭）

| 项 | 结果 | 证据 |
|---|---|---|
| 复核方法 | 关闭 KSM Deployment 后，用 `lag()` 观察"最后一次采样年龄"，并对比 instant 查询（受 VM 5m lookback 影响）与 `count_over_time[60s]` 窗口 | [32-C7f-recheck.md](evidence/20261103-0.2.2-rc.1/32-C7f-recheck.md) |
| 根因 | 验证环境的长期测试 Pod `annotated-metrics-test` 用的是 kube-state-metrics 镜像，**自身也会暴露 `kube_pod_info` 等 kube_* 指标**，并通过 `app-metrics` job 持续上报（本轮实测该来源 16 条 series）。原断言对 `kube_pod_info` 做全量统计，因此永远不会归零 | 同上 §6/§7 |
| 正确判定 | KSM 关闭 120s 后：`kube_pod_info{job="kube-state-metrics"}` = **0**；`kube_pod_info{job="app-metrics"}` = 16（测试 Pod 自带） | 同上 §6 |
| 结论 | **C7f 不是 Chart 缺陷，测试设计问题，关闭** | 同上 §8 |

## 13. rc.3 主 Release 卸载 + 重装演练

| 步骤 | 结果 |
|---|---|
| 卸载前 | rc.3 rev37，3/3 设备在线，series 正常 |
| `helm uninstall` | release 清空；cleanup Hook 删除本集群 3 台设备；**其它集群 3 台设备不受影响** |
| 重新安装（同一份 values） | `REVISION 1` 部署成功，6 个 Pod Running |
| 恢复验证 | 设备 3 台全部 `target_up=2`；series 18,240；`up` 异常 0；`count({owner="platform"})`=18,240；`up{job="app-metrics"}`=1 |
| 结论 | **rc.3 主 Release 的“卸载→清理→重装→重新采集”整链路通过**，8/8 断言 PASS |

证据：[59-rc3-uninstall-reinstall.md](evidence/20261103-0.2.2-rc.1/59-rc3-uninstall-reinstall.md)。

## 14. 正式版发布（0.2.2）

| 项 | 结果 |
|---|---|
| 正式版包 | `categraf-0.2.2.tgz`，SHA256 `7b1b18c01aad2d9a3da29816730ea122dba120399895335d68ddbe5620bcec0f`（初期发布为 `966ec17f…`，同日因镜像升级覆盖重推；与回归执行包 rc.3 的内容差异仅镜像 tag 与 appVersion） |
| OCI 推送 | `registry.flashcat.cloud/public/charts/categraf:0.2.2` 已推送；`latest` 已从 `0.2.1` 更新为 `0.2.2`（覆盖重推后 Digest `sha256:93f5f5b6f010f915eb2af0ac5717a98dc9e0e49c4f75fef17dc01bd233f1573e`） |
| 远端校验 | 覆盖重推后按 `0.2.2` 与 `latest` 各拉回一次，包 SHA256 均 = `7b1b18c01aad2d9a3da29816730ea122dba120399895335d68ddbe5620bcec0f`，与本地一致 |
| 保留版本 | `0.2.1`（上一生产版）与 `0.2.2-rc.3` 仍保留，可回退 |
| 真机验证 | 主测试集群升级到 `0.2.2`（rev2）：版本变化触发 Pod 自动滚动（F1 修复生效）、3/3 设备 `target_up=2`、`up` 异常 0、series 15k+、customLabels 生效 |
| 回滚方式 | `helm upgrade categraf oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1 ...`；如需把 latest 也退回：`oras copy .../categraf:0.2.1 .../categraf:latest` |

证据：[60-publish-ga.md](evidence/20261103-0.2.2-rc.1/60-publish-ga.md)。

## 15. 用户文档同步（飞书）

| 项 | 内容 |
|---|---|
| 文档 | 《K8S 指标采集》 https://c9xudyniiq.feishu.cn/docx/Bddgd2I1Coj3AgxkDHUcndc1nRb |
| 方式 | lark-cli（user 身份）`docs +fetch` / `docs +update`，revision 204 → 210 |
| 改动 | ① kubeVersion 1.21–1.32 → 1.19–1.38；② 拉包固定版本 0.2.1 → **0.2.2**；③ 基础配置新增 customLabels / config / writer / heartbeat；④ 新增「版本提示（0.2.2 起）」；⑤ 新增「升级注意（0.2.2 起 checksum 含渲染配置；旧版本升级需 rollout restart）」；⑥ **纠正卸载说明**（cleanup 默认 true，卸载会删除本集群设备） |
| 顺带修正 | 原文档两处与实际不符：`kubeVersion` 上限 1.32 会使 1.32+ 集群装不上；"卸载默认不删设备"与 Chart 默认值相反 |
| 证据 | [61-feishu-doc-update.md](evidence/20261103-0.2.2-rc.1/61-feishu-doc-update.md) |

## 16. 用户文档精简与「指标自动发现」补充（飞书）

| 项 | 内容 |
|---|---|
| 文档 | 《K8S 指标采集》 https://c9xudyniiq.feishu.cn/docx/Bddgd2I1Coj3AgxkDHUcndc1nRb |
| 方式 | lark-cli `docs +update --command overwrite --doc-format markdown`，revision 210 → **213** |
| 精简 | 合并 2.2/2.3（去掉重复的 33 行 values）、内网部署去掉重复部署命令、控制平面细节移入附录、验证并入 2.3、版本提示集中到第 7 节；原内容等价缩减约 34% |
| 新增 | 第 3 节「指标自动发现（应用指标）」：机制、4 个注解表、标签映射（app/app.kubernetes.io/name → service；team → team）、Deployment 示例、`extraScrapeConfigs` 兜底示例、验证命令与 5 条常见坑，并与附录 A 的“控制平面自动发现”显式区分 |
| 同步 | 仓库 [K8S指标监控.md](../01-k8s-base/K8S指标监控.md) 已按同一版重写，内链校验通过 |
| 证据 | [62-doc-slim.md](evidence/20261103-0.2.2-rc.1/62-doc-slim.md) |

## 17. 镜像升级到最新（版本号仍 0.2.2，覆盖重推）

| 项 | 内容 |
|---|---|
| 变更 | `nodeCategraf.image`: `categraf_ent:servicemap-v0.5.32` → `servicemap-v0.5.45`；`ksmCategraf.image`: `categraf_ent:v0.5.32` → `v0.5.45`；`appVersion`: 0.5.32 → 0.5.45（kube-state-metrics v2.19.1、operator 0.0.7 已是 registry 最新，未变） |
| 渲染差异 | 与旧 0.2.2 相比，归一化后仅 2 行镜像 tag（其它资源零变化） |
| 真机验证 | 主测试集群升级后全部 Pod Running；设备 3/3 `target_up=2`，agent_version 上报 `ent-v0.5.45` / `ent-v0.5.45-servicemap`；`up` 异常 0；series 16,773；customLabels 16,773；无 panic/fatal，仅既有 syslog 已知问题与 benign `dmidecode` 缺失告警 |
| 覆盖重推 | 版本号保持 0.2.2（按用户要求直接覆盖）；镜像升级后本地包 SHA256 `7b1b18c0…`，随后又修正 values.all.yaml 推荐语（纯注释）并再次覆盖，**最终包 SHA256 `8688253178af785d4d1cdf247f2554f574b02577607add0ef8d42ffe4ca3620e`，OCI Digest `sha256:513bb9938f41c07b2e7507ec8486bfafca6a4c4f2220d07bc02535d84b75a742`，`latest` 指向最终包**（最后一次为 values 注释对齐，纯注释改动） |
| 风险 | 同版本覆盖使 digest 变化：已拉过旧 0.2.2 的环境需重新 `helm pull` 才能拿到新镜像；旧包（`966ec17f…`）无法再从仓库取回，仅本地有记录 |
| 证据 | [63-image-upgrade.md](evidence/20261103-0.2.2-rc.1/63-image-upgrade.md) |

## 18. 附录 A「控制平面自动发现」真机验证

| 项 | 结果 |
|---|---|
| 方法 | 备份后修改 kube-controller-manager / kube-scheduler 的 `--bind-address` 与 etcd 的 `--listen-metrics-urls`，开启 `controlPlane.enabled=true`，观察 4 个 job 的 `up` 与指标；测试后完整还原 |
| 结果 | apiserver=1、kube-controller-manager=1、kube-scheduler=1、**etcd=1**（修好防火墙后）；`apiserver_request_total` 351 条、`scheduler_schedule_attempts_total` 1 条、`etcd_server_has_leader` 有数据 |
| 关键发现 | etcd 首次 `up=0` 的根因是 **ufw**：抓取源地址为节点 IP（Flannel SNAT），只放行 Pod 网段不够；按节点网段放通后恢复正常 |
| 还原 | 监听地址恢复 `127.0.0.1`、controlPlane 关闭（job 数 0）、ufw 临时规则删除、设备 3/3 在线 |
| 未覆盖 | A.2「远程下发模式」仍未实测 |
| 证据 | [64-controlplane-a1.md](evidence/20261103-0.2.2-rc.1/64-controlplane-a1.md) |

## 19. 新增 defaultJob 开关 + 修复 extraScrapeConfigs 缩进（F6）

| 项 | 内容 |
|---|---|
| 需求 | 客户希望关闭内置 prometheus.io/* 注解采集，只按自定义注解（AutoMQ 的 prometheus.io/automq-*）采集 |
| 新增开关 | `appMetrics.defaultJob.enabled`（默认 true）；设为 false 只渲染 `extraScrapeConfigs` |
| 发现缺陷 F6 | `extraScrapeConfigs` 渲染缩进错误（`nindent 6`，应为 2）：生成的 scrape 配置非法，KSM Agent 启动时报 `field job_name not found in type relabel.plain`，**集群级采集全部中断**；此前该功能从未在真机验证过 |
| 修复 | 改为 `nindent 2`，与其他 job 缩进一致 |
| 真机验证 | mock AutoMQ Pod（注解 automq-scrape/port/path）→ `up{job="automq"}=1`、`service=automq-mock`、指标 5 条；`app-metrics` 近 1 分钟样本 0（默认 job 已关闭）；无配置加载错误 |
| 还原 | mock Pod 删除；回到 baseline values（REVISION 10），app-metrics job 恢复 |
| 发布 | 0.2.2 覆盖重推：SHA256 `cbc1c7455f39facb1bfb2d9bed3d9c5d05423b2d8f28cbe07f49dd8cc0ffe461`，Digest `sha256:1aaa78360b1196a41da89b1c1d3148f4883e93ada98aa54d90cb54f1d7cd8400`，latest 同步 |
| 证据 | [65-defaultjob-and-f6.md](evidence/20261103-0.2.2-rc.1/65-defaultjob-and-f6.md) |
