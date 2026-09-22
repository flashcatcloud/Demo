# Categraf DaemonSet（Node Agent）

## 1 适用场景

安装K8S Categraf DaemonSet 采集**每个节点**的主机指标、容器指标、kubelet 指标

## 2 前置条件

- Kubernetes >= 1.21 且 < 1.32
- 操作机器已安装 Helm 3、kubelet命令
- 已部署 Flashcat / Nightingale 服务端，获取到服务端地址和业务组 GID
- 集群能拉取仓库registry.flashcat.cloud/public镜像，如果无公网，请手动拉取到内网仓库并修改 `nodeCategraf.image` 参数

## 3 在线安装

```bash
# 默认拉取 latest（最新版）；如需固定版本，加 --version <版本号>
helm upgrade --install categraf oci://registry.flashcat.cloud/public/charts/categraf -n flashcat --create-namespace \
  --set categraf.serverAddr="http://192.168.31.14:19000" \
  --set categraf.heartbeatGid="2" \
  --set categraf.clusterName="Kubernetes-cluster" \
  --set categraf.env="test" \
  --set nodeCategraf.image="registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.32" \
  --set kubeStateMetrics.enabled=false \
  --set ksmCategraf.enabled=false \
  --set appMetrics.enabled=false \
  --set operator.enabled=false
```

**必填参数说明：**

| 参数 | 含义 | 示例 |
| --- | --- | --- |
| `categraf.serverAddr` | Flashcat / Nightingale 服务端地址 | `http://192.168.31.14:19000` |
| `categraf.heartbeatGid` | 业务组 GID | `2` |
| `categraf.clusterName` | 集群名，需全局唯一 | `Kubernetes-cluster` |
| `categraf.env` | 环境标签，如 prod/test | `test` |

> 每个集群的 `clusterName` 必须唯一，否则不同集群的 Agent 标识会冲突。

**上报标识（ident）取值（可选，默认 = K8s 节点名）：**

| 配置 | 效果 |
| --- | --- |
| `nodeCategraf.hostname: nodeName`（默认） | ident = K8s 节点名 |
| `nodeCategraf.hostname: hostname` | ident = 宿主机 hostname |
| `nodeCategraf.hostname: "${cluster}-$hostname"` | 自定义，如 `Kubernetes-cluster-k8s-node1` |

自定义模板可用占位符：`${cluster}`（集群名）、`${nodeName}`（K8s 节点名）、`$hostname`（宿主机 hostname）、`$ip`（节点 IP）。

## 4 离线安装

```bash
# 下载并解压 Chart 包
helm pull oci://registry.flashcat.cloud/public/charts/categraf   # 默认拉取 latest（最新版）
tar xvf categraf-*.tgz

# 安装（镜像地址按需换成内网仓库）
helm upgrade --install categraf ./categraf -n flashcat --create-namespace \
  --set categraf.serverAddr="http://192.168.31.14:19000" \
  --set categraf.heartbeatGid="2" \
  --set categraf.clusterName="Kubernetes-cluster" \
  --set categraf.env="test" \
  --set nodeCategraf.image="你的内网仓库/categraf_ent:servicemap-v0.5.32" \
  --set kubeStateMetrics.enabled=false \
  --set ksmCategraf.enabled=false \
  --set appMetrics.enabled=false \
  --set operator.enabled=false
```

## 5 验证

```bash
# 查看 Pod
kubectl get pods -n flashcat -o wide

# DaemonSet 覆盖的 Pod 数应等于节点数
kubectl get pods -n flashcat -l component=categraf --no-headers | wc -l
kubectl get nodes --no-headers | wc -l

# 查看日志
kubectl logs -n flashcat -l component=categraf --tail=20
```

## 6 卸载

```bash
helm uninstall categraf -n flashcat --ignore-not-found
kubectl delete namespace flashcat --ignore-not-found
kubectl delete clusterrole categraf-flashcat-node-agent --ignore-not-found
kubectl delete clusterrolebinding categraf-flashcat-node-agent --ignore-not-found
```


## 7 安全上下文：方案 A / 方案 B（命令通道支持）

Node Agent 容器默认以 **方案 A（privileged=true）** 运行，这也是 FlashAI 命令通道 R0 巡检 / 定位与 W1/W2 自愈的推荐形态（privileged 提供 dmesg 所需的 SYSLOG、chroot 所需的 SYS_CHROOT，并允许 nsenter 等写宿主操作）。

两个方案的区别：

| 能力 | 方案 A（privileged: true，默认） | 方案 B（privileged: false） |
| --- | --- | --- |
| 节点/容器指标采集、读宿主文件/日志 | ✅ | ✅ 一样 |
| servicemap 服务地图采集（eBPF：HTTP/MySQL/Redis 等 L7） | ✅ | ❌ 自动降级为轮询（无 L7 解析） |
| dmesg / 内核日志 | ✅ | ✅（保留 SYSLOG） |
| 以宿主机视角执行命令（chroot /hostfs：systemctl / journalctl / ss 等） | ✅ | ❌ 默认不可（需显式加回 SYS_CHROOT） |
| 修改宿主机（重启服务、清理磁盘等） | 技术上可行（受平台授权 R0/W1/W2 约束） | ❌ 物理不可达 |
| 适合场景 | 功能全，推荐 | 只做只读巡检、安全要求高 |

如需收敛权限，可在 `my-values.yaml` 中切换到 **方案 B**，只需写 `privileged: false`，chart 会自动补全收窄配置（`allowPrivilegeEscalation: false` + `drop: ["ALL"]` + `add: ["SYSLOG"]`），并按 `privileged` 自动注入环境变量 `CATEGRAF_HOST_EXEC_PROFILE`（方案 A 为 `true`、方案 B 为 `false`），categraf / FlashAI 据此判断是否可执行宿主机命令：

```yaml
nodeCategraf:
  securityContext:
    privileged: false
```

如需自定义（例如额外加 cap），可整段覆盖：

```yaml
nodeCategraf:
  securityContext:
    privileged: false
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
      add: ["SYSLOG", "SYS_CHROOT", "SYS_PTRACE"]
```

注意：

- 方案 B 仅支持只读巡检 / 定位（dmesg 可读），默认不再授予 `SYS_CHROOT`，脚本不会以宿主机视角执行，写宿主操作物理不可达；如需保留 `chroot /hostfs` 能力，请在 capabilities 中显式加回 `SYS_CHROOT`（见下方自定义示例）。切换前请先完成一轮插件指标完整性验证（个别指标依赖 ptrace / /dev 设备）再推广。
- 无论 A/B，Pod 级仍使用 hostPath + hostPID + hostNetwork，若集群启用了 Pod Security Admission（baseline / restricted），本命名空间需标注 `pod-security.kubernetes.io/enforce=privileged`，否则 Pod 无法创建。

**host-exec 命令通道（FlashAI 下发脚本进入宿主机执行）** 默认开启（与默认 privileged=true 的形态一致）；不需要时改为 `false`：

```yaml
nodeCategraf:
  hostExec:
    enabled: false
```

开启后 chart 自动渲染 `privileged: true`、`CATEGRAF_HOST_EXEC_PROFILE=true`，并挂载宿主机 `/var/lib/categraf/ibex`（任务脚本先写入该目录，再在宿主上下文执行，容器内外路径一致、不使用 subPath）；`/hostfs` 挂载启用 `mountPropagation: HostToContainer`。
