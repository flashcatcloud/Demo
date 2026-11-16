# Categraf 0.2.3 重建集群与采集验证

> 本记录对应 `0.2.3` **内部测试构建**，从未推送到 OCI 仓库，也不是发布版本；其变更（annotation 应用发现、`appMetrics.extraScrapeConfigs`）已并入测试候选 [`0.2.2-rc.1`](categraf-0.2.2-rc.1-20261103.md)，后续正式版本为 `0.2.2`。版本号规则见 [发布 Chart 到 OCI 仓库](../附录/发布Chart到仓库.md)。

## 1. 基本信息

| 项 | 值 |
|---|---|
| 初次验证 | 2026-10-29 |
| 完整回归 | 2026-11-03 |
| Kubernetes | v1.28.2，kubeadm + containerd 2.2.1 + Flannel |
| 控制平面 | `k8s-node1` / `192.168.31.5` |
| Worker | `k8s-node2` / `192.168.31.6` |
| Chart | `categraf-0.2.3` |
| Chart SHA256 | `717e55ccec88d3d2f70c1b158326fc9344403a446d5b7431fe35ba1c81f8216a` |
| 命名空间 | `categraf` |
| Helm Release | `categraf`，最终 revision 7 |
| Flashcat 地址 | `http://flashcat.local:19000` |
| 集群名 | `k8s-flashcat-test-20261029` |
| 业务组 GID | `2` |
| Operator | 启用 |

## 2. 集群与网络

- 旧 Kubernetes 状态已清理并重新初始化。
- `k8s-node1` 和 `k8s-node2` 均为 `Ready`。
- Pod CIDR：`10.244.0.0/16`。
- CNI：Flannel，两个节点 DaemonSet 均为 Running。
- CoreDNS 增加内部解析：`flashcat.local -> 192.168.31.14`。
- UFW 保持启用，仅放行 Kubernetes 所需端口。

## 3. 回归结果

| 检查项 | 结果 |
|---|---|
| `helm lint categraf-0.2.3.tgz` | 通过 |
| Helm Release 状态 | `deployed` |
| Node Agent | 2 个 Pod，Running/Ready |
| KSM Agent | 1 个 Pod，Running/Ready |
| kube-state-metrics | 1 个 Pod，Running/Ready |
| Operator | 1 个 Pod，Running/Ready，成功获得 Leader Lease |
| Flashcat targets API | 通过 |
| Flashcat 设备 | NodeAgent x2 + KSMAgent x1，均为 `target_up=2` |
| 标准 annotation 自动发现 | 通过，`app-metrics` target 为 `up` |
| 实际抓取 URL | `http://<pod-ip>:8080/metrics` |
| 长期 annotated 测试 Pod | `categraf/annotated-metrics-test`，target 为 `up` |
| 自动发现结果标签 | `service=annotated-metrics-test`、`team=platform`、`pod`、`namespace` 正确 |
| `appMetrics.extraScrapeConfigs` | 通过，额外 job target 为 `up` |
| `categraf.customLabels` | 模板验证通过，Node/KSM 和 external_labels 均正确 |
| 非法 customLabels | 通过，保留标签覆盖会明确失败 |
| Node Agent Pod 自愈 | 通过 |
| KSM Agent Pod 自愈 | 通过 |
| Operator Pod 自愈 | 通过，重建后重新获得 Leader Lease |
| `prometheus_remote_storage_samples_failed_total` | `0` |
| `prometheus_remote_storage_samples_pending` | `0` |
| Node Agent 到 Flashcat 连接 | 存在到 `192.168.31.14:19000` 的 ESTAB 连接 |

验证过程中发现并修复了以下 Chart 问题：

- `prometheus.io/path` relabel 缺少捕获组，导致路径被覆盖为空。
- `app-metrics` 未设置任务级默认 `metrics_path`。

最终 Chart 包已包含修复。

## 4. 未覆盖项目

以下破坏性操作尚未执行，需要单独授权：

- `helm uninstall` 及设备 cleanup 验证。
- 卸载后重新安装。
- 节点重启及离线节点清理。
- 从旧版本执行正式升级回滚演练。

## 5. 已知问题

- Node Agent 的 syslog collector 仍周期性报 `failed to execute tail command`；不影响 CPU、内存、磁盘、网络、Kubernetes 和应用指标采集。后续单独处理。

## 6. 产物位置

- Chart 包：`k8s-node1:/root/categraf-0.2.3.tgz`。
- 正式回归 values：`k8s-node1:/root/categraf-regression-values.yaml`。
- `extraScrapeConfigs` 临时回归 values：`k8s-node1:/root/categraf-extra-regression-values.yaml`。
- 长期 annotated 测试清单：`assets/examples/annotated-metrics-test.yaml`。
