# K8S日志采集

日志采集分为两类，分工建议如下：

|日志类型|负责方|采集方式|
|---|---|---|
|节点操作系统日志（syslog/messages）|K8s 运维|DaemonSet log 插件，控制台远程下发|
|容器 stdout/stderr|K8s 运维|DaemonSet 自动发现 + 控制台创建采集任务|

建议：节点系统日志和容器标准输出由 K8s 运维统一采集。

## 1. 前置条件

- 已通过 Helm Chart 部署 Categraf（详见 [K8S指标监控](K8S指标监控.md)），Node Agent DaemonSet 已覆盖所有节点。
- Categraf 镜像需包含 log 插件（企业版默认已集成）。
- Node Agent 需挂载宿主机目录，用于读取节点系统日志和容器日志。Helm Chart 默认已挂载 `/hostfs`。
- `/hostfs` 是宿主机根目录 `/` 在 Categraf 容器内的挂载点，因此容器内 `/hostfs/var/log/xxx` 对应宿主机上的 `/var/log/xxx`。
- Helm Chart 默认已通过空 ConfigMap 禁用镜像自带的 `input.syslog` 插件，避免默认 syslog 路径在容器内 tail 失败。如需采集节点系统日志，应使用下文**文件采集**方式并指定 `/hostfs` 路径。

## 2. 节点操作系统日志采集

操作系统日志（如 `/var/log/syslog`）通过**文件采集**方式收集，在 Flashcat 控制台创建日志采集任务即可。

不同 Linux 发行版的系统日志文件路径不同，常见如下：

| 发行版 | 系统综合日志 | 安全/认证日志 |
|---|---|---|
| Ubuntu/Debian | `/var/log/syslog` | `/var/log/auth.log` |
| CentOS/RHEL/Alibaba Cloud Linux | `/var/log/messages` | `/var/log/secure` |

**配置示例**（Ubuntu/Debian）：

```TOML
[[items]]
type = "file"                    # 固定值，表示文件采集模式
source = "file"                  # 自定义标签，标识日志来源
path = "/hostfs/var/log/syslog"  # 日志文件路径（通过宿主机的 /hostfs 挂载点访问）
service = "node-syslog"          # 自定义标签，标识服务名称
```

CentOS/RHEL 系列可改为：

```TOML
[[items]]
type = "file"
source = "file"
path = "/hostfs/var/log/messages"
service = "node-messages"
```

**说明**：

- `type = "file"` 表示采用文件采集模式。
- `path` 通过 `/hostfs` 前缀访问宿主机文件系统，读取节点系统日志。
- 此方式采集的是节点级别的系统日志，与容器无关。

**验证**：

1. 在 Flashcat 控制台查看日志采集任务状态是否为 **运行中**。
2. 进入日志检索页面，按 `service="node-syslog"` 查询，确认日志持续上报。

---

## 3. 容器标准输出日志采集（Pod）

容器 stdout/stderr 日志由 **Node Agent DaemonSet 自动发现所有 Pod**，K8s 运维在 Flashcat 控制台创建日志采集任务时，通过 **namespace + label** 组合匹配目标 Pod。

**配置示例**（采集全部命名空间）：

```TOML
[[items]]
type = "pod"                              # 固定值，表示 Pod 日志采集模式
source = "K8s"                            # 自定义标签，标识日志来源为 K8s
service = "k8s-pod-logs"                  # 用户自定义标签，仅用于日志分类和检索，可任意命名
container_logs_parser = "containerd"      # 指定容器运行时日志格式
```

**说明**：

- `type = "pod"` 表示采用 Pod 日志采集模式，采集器自动读取 `/var/log/pods/` 和 `/var/log/containers/` 下的容器日志。
- `service` 是**用户自定义字符串标签**。后续在 Flashcat 日志检索页按 `service="k8s-pod-logs"` 即可过滤出这批日志，名称可随意改。
- 通过 `filter_rules` 配置 namespace 和 label 规则来筛选目标 Pod；不写 `filter_rules` 表示采集所有命名空间。
- `container_logs_parser` 需与集群实际容器运行时保持一致，可选值：`containerd`、`docker`、`podman`。

### 3.1 采集全部命名空间

不写 `filter_rules` 即可采集所有 Pod：

```TOML
[[items]]
type = "pod"
source = "K8s"
service = "k8s-pod-logs"
container_logs_parser = "containerd"
```

### 3.2 指定某个命名空间

```TOML
[[items]]
type = "pod"
source = "K8s"
service = "prod-logs"
container_logs_parser = "containerd"

[[items.filter_rules]]
source_labels = ["pod_namespace"]
regex = "production"
action = "keep"
```

### 3.3 namespace + label 组合筛选

如需筛选特定命名空间或带特定标签的 Pod，可添加 `filter_rules`：

```TOML
# 采集 demo 命名空间的 test_gateway
[[items]]
type = "pod"
source = "K8s"
service = "test-gateway-logs"
container_logs_parser = "containerd"

[[items.filter_rules]]
source_labels = ["pod_namespace"]
regex = "demo"
action = "keep"

[[items.filter_rules]]
source_labels = ["label_app"]
regex = "test-gateway"
action = "keep"
```

多个 `filter_rules` 之间是**并且（AND）**关系，必须同时满足才会采集。

`filter_rules` 支持的常用标签：

| 标签 | 说明 |
|---|---|
| `pod_namespace` | Pod 所属命名空间 |
| `pod_name` | Pod 名称 |
| `label_app` | Pod 上的 `app` label 值 |
| `label_team` | Pod 上的 `team` label 值 |
| `container_name` | 容器名称 |

**验证**：

1. 在 Flashcat 控制台查看日志采集任务状态是否为 **运行中**。
2. 进入日志检索页面，按 `service="k8s-pod-logs"` 查询，确认目标 Pod 日志持续上报。
3. 若未采集到数据，检查 `container_logs_parser` 是否与集群运行时一致，以及 `filter_rules` 是否过滤了目标 Pod；必要时临时去掉 `filter_rules` 测试。

---

## 4. 常见问题

| 现象 | 可能原因 | 解决方法 |
|---|---|---|
| 日志任务运行中但无数据 | `filter_rules` 过滤条件不匹配 | 检查 namespace 和 label 拼写，或临时去掉 `filter_rules` 测试 |
| 日志内容乱码 | 日志编码非 UTF-8 | 在 Categraf 配置中调整 `charset` 参数 |
| 多行日志被拆散 | 未配置多行合并规则 | 在采集任务中配置 `multiline` 规则，如 Java 异常堆栈合并 |
| 日志延迟高 | 采集间隔或批量参数不合理 | 调整 `interval` 和 `batch_size` 参数 |

补充：若日志中出现 `collector failed name syslog err failed to execute tail command: exit status 1`，说明 `input.syslog` 插件正在尝试用默认路径采集系统日志但失败了。使用本 Chart 时该插件默认已被禁用，如仍看到报错，请确认是否使用了旧版本 Chart，或执行 `helm upgrade` 重新部署。

## 5. Categraf 重启与日志偏移量

Categraf 重启后是否丢日志，取决于 log 插件的状态是否持久化。

### 5.1 默认情况

当前 Chart 默认未给 Categraf 挂载持久化状态目录。容器重启后，log 插件的偏移量会丢失，新的 Categraf 会从当前日志文件末尾继续 tail，**停机期间产生的日志可能采集不到**，重启前未发送成功的日志也可能重复上报。

### 5.2 持久化状态（可选）

如果业务对日志完整性要求较高，可以自行在 Chart 中为 Categraf 挂载一个宿主机目录作为状态目录，例如：

```yaml
# 在 node-categraf.yaml 的 volumeMounts 和 volumes 中增加
volumeMounts:
- mountPath: /opt/categraf/state
  name: categraf-state

volumes:
- hostPath:
    path: /var/lib/categraf
    type: DirectoryOrCreate
  name: categraf-state
```

然后在日志采集任务中，将状态文件路径指向 `/opt/categraf/state` 下的某个文件。

### 5.3 注意事项

| 场景 | 影响 |
|---|---|
| 容器自动重启 | 默认会丢失停机期间日志，可能少量重复 |
| 配置了持久化 state | 重启后从上次位置继续，基本不丢不重复 |
| Node 删除/迁移 | DaemonSet Pod 会调度到其他节点，日志是节点本地文件，无法跨节点续读 |
