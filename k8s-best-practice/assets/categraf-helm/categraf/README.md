# Categraf Helm Chart

在 Kubernetes 集群中部署 Categraf 节点采集、Kube-State-Metrics、KSM Agent 和可选的节点清理 Operator。

## 支持的 Kubernetes 版本

```text
kubeVersion: ">=1.21.0-0 <1.32.0-0"
```

当前版本已在 Kubernetes 1.28 环境完成安装、卸载和重新上报验证。

## 组件

| 组件 | 工作负载 | 说明 |
|---|---|---|
| Node Agent | DaemonSet | 采集节点、kubelet、cAdvisor、kube-proxy 和主机指标 |
| Kube-State-Metrics | Deployment + Service | 暴露 Kubernetes 对象状态指标 |
| KSM Agent | StatefulSet | 采集 KSM 指标并写入 Flashcat / Nightingale |
| Operator | Deployment | 清理已删除节点在 Flashcat 上的残留设备 |

## 前置条件

- Kubernetes `>=1.21.0-0 <1.32.0-0`
- Helm 3
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

## 资源命名

- 命名空间级资源使用 `<release>-<component>`，Node Agent DaemonSet 使用 `<release>`。
- 集群级 ClusterRole 和 ClusterRoleBinding 使用 `<release>-<namespace>-<component>`。
- 所有命名空间级资源显式使用 `.Release.Namespace`。

## Release 命名与升级说明

- 命名空间级资源名使用 `<release>-<component>`，Node Agent DaemonSet 使用 `<release>`。
- Workload 和 Service selector 包含 `app.kubernetes.io/instance=<release>`。
- ClusterRole / ClusterRoleBinding 使用 `<release>-<namespace>-<component>`。
- Operator 的 leader election Lease 仍使用固定名称，本版本按“一个集群一个 Release”运行，不提供同 namespace 多 Release 的完整隔离。

> 本次为 `0.2.1` 同版本覆盖更新。Workload selector 新增了 `app.kubernetes.io/instance`，而 Deployment/StatefulSet/DaemonSet 的 selector 不可变。已有 `0.2.1` 环境不能直接 `helm upgrade`，必须执行“备份 values -> 卸载旧版本 -> 安装新版本”；全新安装不受影响。

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
