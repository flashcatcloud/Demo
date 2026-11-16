# CMD: G7 文档一致性：chart README / K8S指标监控.md / values-examples / 测试记录 README 与实测对照
# AT: 2026-11-03T06:10:29Z / 2026-11-03T14:10:29+0800

## 7.1 Chart.yaml 与 chart README 的 kubeVersion 是否一致
```
Chart.yaml:      kubeVersion: ">=1.19.0-0 <1.38.0-0"
README 中的声明: kubeVersion: ">=1.19.0-0 <1.38.0-0"
```
## 7.2 README 声称的“已验证范围” vs 实测矩阵（01-static.md 1.4）
```
README 声明: - 已验证范围：模板渲染在 1.19 / 1.21 / 1.28 / 1.32 / 1.36 / 1.37 均通过（`helm template --kube-version`）；实际集群安装、卸载和重新上报在 Kubernetes 1.28.2 验证。1.32 以上版本未在真实集群回归，仅保证模板渲染通过。

实测矩阵（来自 01-static.md）:
```
## 7.3 README 版本历史与 values.yaml 实际功能对照
```
  values.yaml 含 customLabels           : 1
  values.yaml 含 extraScrapeConfigs     : 1
  values.yaml 含 config:                : 1
  values.yaml 含 chanSize               : 1
  values.yaml 含 dialTimeout            : 1
  values.yaml 含 heartbeatGid           : 1

README 版本历史段:
  > **版本号规则**：正式版本（如 `0.2.1`、下一版 `0.2.2`）才推送到 OCI 仓库并允许更新 `latest`；测试候选用预发布后缀（`0.2.2-rc.1`、`0.2.2-rc.2`…），只打版本 tag，不更新 `latest`。详见 [发布 Chart 到 OCI 仓库](../../../docs/附录/发布Chart到仓库.md)。
  >
  > `0.2.2-rc.1`（测试候选，当前内容）汇总了此前未发布的三批内部构建改动：`categraf.customLabels`、annotation 应用发现 + `appMetrics.extraScrapeConfigs`、少量结构化运行时参数（`categraf.config.interval` / `writer.batch` / `writer.chanSize` / `heartbeat.*`），并修正了 `kubeVersion`（`>=1.19.0-0 <1.38.0-0`）与 `appVersion`（`0.5.32`）。生产版本仍为 `0.2.1`，可从 `0.2.1` 直接 `helm upgrade`。
```
## 7.4 K8S指标监控.md 的拉包版本 / kubeVersion / 版本提示
```
$ 文档中的 helm pull 命令
17:helm pull oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1
21:# helm pull oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.2-rc.1
$ 文档中的 kubeVersion 描述
7:- Kubernetes >= 1.19 且 < 1.38，本机已安装 Helm 3
$ 文档中的版本提示（0.2.2 起）
77:> **版本提示**：`customLabels`、`appMetrics.extraScrapeConfigs` 以及下面的结构化运行时参数都是 **0.2.2 起**才提供的。生产版本 `0.2.1` 会忽略这些字段（不报错、也不生效）；需要使用它们请显式拉取测试候选 `0.2.2-rc.1`，等 `0.2.2` 正式发布后再按生产版本使用。
$ 仓库中 0.2.1 是否真实存在
version: 0.2.1
```
## 7.5 values-examples 注释与 Chart 默认值是否一致
```
values-examples/values.yaml 声明: chart 自带默认 coreDns/networkPlugin/kubeProxy 是开的
chart values.yaml 实际默认:
      enabled: true
  coreDns:
    calico:
      enabled: true
    cilium:
      enabled: true
  kubeProxy:
--- 逐项核对 ---
  coreDns.enabled = true
  kubeProxy.enabled = true
  controlPlane.enabled = false
  appMetrics.enabled = true
  kubeStateMetrics.enabled = true
  ksmCategraf.enabled = true
  nodeCategraf.enabled = true
  networkPlugin.calico.enabled = true
```
## 7.6 测试验证记录命名规则 vs 实际文件名
```
  categraf-0.2.1-20260922.md
  categraf-0.2.2-rc.1-20261103.md
  categraf-0.2.3-20261029.md

规则（记录 README）: 21:- 文件名格式：`categraf-<Chart 版本>-<YYYYMMDD>.md`，其中版本号与 `Chart.yaml` 的 `version` 一致。
```
## 7.7 外部共享文档：test-env skill 中 cleanup 默认值描述
```
$ grep cleanup 默认值描述（~/.codex/skills/test-env 与 ~/.agents 副本）
  /Users/flashcat/.codex/skills/test-env/SKILL.md:58:- `operator.cleanup.nodeCategraf` / `ksmCategraf` default to `false`; only enable them when the user explicitly asks to test uninstall device cleanup, and warn that the release's Flashcat devices will be deleted on uninstall.
  /Users/flashcat/.agents/skills/test-env/SKILL.md:58:- `operator.cleanup.nodeCategraf` / `ksmCategraf` default to `false`; only enable them when the user explicitly asks to test uninstall device cleanup, and warn that the release's Flashcat devices will be deleted on uninstall.

chart 实际默认值:     # 删除该集群的 nodeCategraf 设备（nodeAgent targets，DaemonSet 部署）     nodeCategraf: true     # 删除该集群的 ksmCategraf 设备（ksmAgent targets，StatefulSet 部署） 
本次实测（G2 卸载）：cleanup hook 主动删除了 3 个设备（见 10-lifecycle.md），证明默认开启生效
```
## 7.8 差异汇总
```
本次核对发现的文档差异（需修复项）：
  （由执行者逐条填写；无差异则显示“无”）
```
