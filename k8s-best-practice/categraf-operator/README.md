# categraf-operator

清理 K8s 节点删除后 Flashcat 上残留的 categraf 设备。

## 工作流

```
Node Delete 事件 (Watch)
   ↓
打标签: categraf_node_gone=true + deleted_at 时间戳
加入内存队列
   ↓
等待观察期 (默认 24h)
   ↓
验证心跳已停 + ident 唯一性检查
   ↓
从 Flashcat 删除设备（标签随设备一并消失）
```

定时循环（可配置，默认每 5 分钟）额外执行：

1. **扫描 Flashcat 上所有带 `categraf_node_gone` 标签的设备** — 用于重启后恢复队列
2. **检测失联节点** — Node 长期 NotReady/Unknown 超过阈值（默认 7 天）触发下线
3. **清理等待期已过的 pending 设备**

## 触发机制与容灾设计

三条触发路径覆盖不同场景，互为补充：

| 触发路径 | 覆盖场景 | 说明 |
|---|---|---|
| **Node 删除事件**（informer Watch） | 正常 `kubectl delete node` / 集群缩容 | 主路径，实时触发 |
| **reconcile 全量对比** | operator 错过了删除事件 | 对比 K8s Node 列表与 Flashcat 设备列表，凡"Flashcat 有、K8s 没有"的设备补打标签入队 |
| **失联节点检测**（`MAX_NODE_STALE_DURATION`） | 机器已死但 Node 对象残留在集群里 | Node 持续 NotReady/Unknown 超过阈值（如机器断电、云主机被直接销毁但没走 kubectl 流程），视同报废触发清理 |

**典型容灾场景——operator 所在节点自身被删除**：

删除事件到达时 operator 可能已随节点一起死亡，事件丢失、内存队列也丢失。operator 被调度到其他节点重启后，由两层机制兜底，功能上不会漏，只是比事件路径慢一个扫描周期：

1. **启动/每轮 reconcile 的全量对比**发现原节点已从 K8s 消失，补打 `gone` 标签入队；
2. **启动恢复扫描**重建队列：扫描 Flashcat 中所有带 `categraf_node_gone=true` 的设备，按标签里记录的 `deleted_at` 原时间继续等待（不重新计时）。

**关于 `MAX_NODE_STALE_DURATION` 是否可关**：

- 全量对比只兜"Node 对象已被删除"的情况；**机器没了但 Node 对象残留**的场景只有失联检测能兜住；
- 如果环境保证"机器下线一定删 Node 对象"（如全自动化纳管），可设 `"0"` 关闭；
- 人工维护的集群或云主机可能被直接销毁的环境，建议保留。

## 认证

仅需 `X-User-Token` header，不需要 Bearer token。

```bash
kubectl create secret generic categraf-operator-secret \
  -n flashcat \
  --from-literal=user-token="<your-api-key>"
```

## 快速开始

```bash
# 1. 部署 RBAC
kubectl apply -f deploy/rbac.yaml

# 2. 配置 Flashcat 地址
kubectl edit configmap categraf-operator-config -n flashcat
# 修改 FLASHCAT_ADDR 为实际地址，如 http://192.168.31.14:19000

# 3. 配置 API Key
kubectl create secret generic categraf-operator-secret \
  -n flashcat \
  --from-literal=user-token="<your-api-key>"

# 4. 部署
kubectl apply -f deploy/configmap.yaml
kubectl apply -f deploy/deployment.yaml
```

## 配置项

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `FLASHCAT_ADDR` | `http://127.0.0.1:19000` | Flashcat 服务地址 |
| `FLASHCAT_USER_TOKEN` | (Secret) | X-User-Token API Key |
| `CLUSTER_NAME` | `Kubernetes-cluster` | 集群名，拼入设备 ident `${CLUSTER_NAME}-${nodeName}` |
| `DEFAULT_WAIT_DURATION` | `24h` | 下线到删除的观察期 |
| `HEARTBEAT_INTERVAL` | `10s` | categraf 心跳间隔（用于判断心跳是否已停） |
| `HEARTBEAT_STOP_FACTOR` | `3` | 心跳停止判定倍数：`now - lastHeartbeat > interval × factor` |
| `RECONCILE_INTERVAL` | `5m` | 定时扫描间隔 |
| `MAX_NODE_STALE_DURATION` | `168h` (7天) | 失联节点兜底检测，设为 `0` 关闭 |
| `NAMESPACE` | `flashcat` | 部署命名空间 |
| `CATEGRAF_DAEMONSET_NAME` | `categraf` | 要 Watch/停用的 nodeAgent DaemonSet 名 |
| `CATEGRAF_KSM_STATEFULSET_NAME` | `categraf-ksm` | 卸载时要停用的 ksmAgent StatefulSet 名 |
| `CATEGRAF_OPERATOR_DEPLOYMENT_NAME` | `categraf-operator` | 卸载时要停用的 operator Deployment 名 |
| `CLEANUP_HEARTBEAT_TIMEOUT` | `2m` | 卸载清理等待设备心跳停止的最长时间 |

## 卸载清理（helm uninstall / 手动删 DS）

- **`helm uninstall`**：chart 内置 `pre-delete` hook Job，卸载时先于所有资源删除执行 `--cleanup-once`：停用 nodeAgent DaemonSet 与 ksmAgent StatefulSet → 等设备心跳停（≤`CLEANUP_HEARTBEAT_TIMEOUT`）→ 删本集群设备。hook 失败会中止卸载（可用 `helm uninstall --no-hooks` 强删）。
- **手动 `kubectl delete daemonset`（operator 存活）**：由 informer 兜底触发，仅清理 nodeAgent（ksm 只在完整卸载时清理）。
- **多集群防误删**：删除目标前做 ident 唯一性确认；`CLUSTER_NAME` 使用默认值且开启清理时启动日志告警（共享同一 Flashcat 时务必设置全局唯一集群名）。业务组由 Flashcat 控制台人工管理，operator 不会删除。

## 安全机制

- **心跳二次确认**：删除前检查 `target_up` 和 `unixtime`，确保设备心跳真停了
- **ident 唯一性检查**：列出所有同 ident 的设备，如有仍活跃的则不删（避免跨集群 ident 重复导致误删）
- **删除前打标签**：节点删除时立即标记，方便人工排查

## 构建

```bash
make build    # 本地交叉编译 linux/amd64
make docker   # 构建 Docker 镜像
make test     # 运行测试
```
