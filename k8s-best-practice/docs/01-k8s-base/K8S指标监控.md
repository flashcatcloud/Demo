# K8S 指标监控采集（Helm 版）

一键部署 Categraf 到 Kubernetes，采集节点、K8s 对象状态、组件和应用指标并上报 Flashcat / Nightingale。

## 1 前置条件

- Kubernetes >= 1.21 且 < 1.32，本机已安装 Helm 3
- 已部署 Flashcat / Nightingale，拿到服务端地址和业务组 GID
- 集群可拉取镜像（无法访问公网镜像时见 [内网部署](#3-内网部署可选)）

## 2 快速部署（3 步）

### 2.1 拉包解压

```bash
# 推荐固定版本
helm pull oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1
tar xvf categraf-0.2.1.tgz
```

### 2.2 选择监控范围，复制配置

Chart 内置一份开箱即用配置 `categraf/values-examples/values.yaml`，按「基础配置 / 节点级采集 / 集群级采集 / K8s 组件」四段组织，除 K8s 组件外默认全部安装并启用：

```bash
cp categraf/values-examples/values.yaml my-values.yaml
```

### 2.3 填写必填区并部署

```bash
vim my-values.yaml
```

文件头部「基础配置」只需改 2 个必填值，其余按需：

```yaml
categraf:
  serverAddr: "http://192.168.31.14:19000"   # 必填：Flashcat 服务端地址
  heartbeatGid: "2"                          # 可选：业务组 GID，配置后自动归入该业务组；不配则上报到未分组，可在 Flashcat 网页端手动管理
  clusterName: "Kubernetes-cluster"          # 必填：集群名，需全局唯一
  env: "test"                                # 可选：环境标签，如 prod / test

# 想自动清理已删除节点的设备，把 operator.userToken 填上；不需要则把 operator.enabled 改为 false
operator:
  enabled: true
  userToken: ""                              # 清理已删除节点的设备；enabled=true 时必填

# Node Agent 可选（一般保持默认即可）：
#   上报标识(ident)默认取 K8s 节点名；要宿主机名改 hostname: hostname，要自定义如 "${cluster}-$hostname"
#   privileged: true（默认，推荐）= 功能全；false = 功能受限：只能看/查，不能执行宿主命令/改宿主（servicemap 会降级）
nodeCategraf:
  hostname: nodeName
  securityContext:
    privileged: true
  # FlashAI host-exec 命令通道（默认开）：不需要时改为 false
  hostExec:
    enabled: true
```
> 如需启用/关闭某个采集任务，直接编辑 `my-values.yaml` 中对应的开关即可（每个开关都有注释说明），改完重新执行部署命令生效。例如开启coreDns组件监控，把 `coreDns.enabled`改成true即可


```bash
helm upgrade --install categraf ./categraf -n flashcat --create-namespace -f my-values.yaml
```

## 3 内网部署

集群无法访问公网镜像时，可以先将以下 4 个镜像同步到内网仓库：

- **kube-state-metrics**：`registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1`
- **ksmCategraf（KSM Agent）**：`registry.flashcat.cloud/public/categraf_ent:v0.5.32`
- **nodeCategraf（Node Agent）**：`registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.32`
- **operator**：`registry.flashcat.cloud/public/categraf-operator:0.0.7`

默认镜像均位于 `registry.flashcat.cloud/public`。完成镜像同步后，基于章节 2 的步骤，在 `my-values.yaml` 中覆盖以下镜像地址：

```yaml
operator:
  image: "<mirror>/categraf-operator:0.0.7"

nodeCategraf:
  image: "<mirror>/categraf_ent:servicemap-v0.5.32"

ksmCategraf:
  image: "<mirror>/categraf_ent:v0.5.32"

kubeStateMetrics:
  image: "<mirror>/kube-state-metrics:v2.19.1"
```

然后重新执行部署命令：

```bash
helm upgrade --install categraf ./categraf -n flashcat --create-namespace -f my-values.yaml
```

注意：镜像版本应与 Chart 默认版本保持一致；同步镜像时需同时覆盖集群节点的 CPU 架构，例如 `linux/amd64` 或 `linux/arm64`。


## 4 自建集群组件监控补充（可选）

网络相关组件 CoreDNS、kube-proxy、Calico / Cilium 已集成到 Helm Chart，在 `my-values.yaml` 里把对应开关改为 `true` 并重新部署即自动采集，无需额外配置。

控制平面组件（apiserver / controller-manager / scheduler / etcd）有两种采集模式：

- **自动发现模式**：适用于 kubeadm 集群，需先放开 Master 组件监听地址（见 4.1）
- **远程下发模式**：kubeadm 和二进制手动部署均适用，无需改监听地址（见 4.2）

> **kubeadm 集群**：用 kubeadm 工具搭建，控制平面组件以 Static Pod 方式运行；**二进制手动部署集群**：手动安装组件二进制，以 systemd 服务方式运行。

### 4.1 自动发现模式（仅 kubeadm 集群）

1. 放开 Master 组件监听地址：

```bash
# controller-manager / scheduler
sudo sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/g' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml \
  /etc/kubernetes/manifests/kube-scheduler.yaml

# etcd metrics 监听地址（若 etcd.yaml 里没有这行，请手动追加 --listen-metrics-urls=http://0.0.0.0:2381）
sudo sed -i \
  's/--listen-metrics-urls=http:\/\/127.0.0.1:2381/--listen-metrics-urls=http:\/\/0.0.0.0:2381/' \
  /etc/kubernetes/manifests/etcd.yaml

#查看端口监听情况（应显示监听在 `0.0.0.0`） 

sudo ss -tlnp | grep -E '10257|10259|2381'
```

> 改完 manifest 后 kubelet 会自动重建对应 Static Pod，无需手动重启；若长时间未生效，可 `kubectl delete pod -n kube-system <controller-manager|scheduler|etcd>-<节点名>` 触发重建。

2. 开启控制平面采集：在 `my-values.yaml` 里把 `controlPlane.enabled` 改为 `true`（CoreDNS / 网络插件同理）。

3. 重新执行部署命令，并重启 KSM Agent 加载新配置：

```bash
helm upgrade categraf ./categraf -n flashcat -f my-values.yaml
kubectl rollout restart statefulset categraf-ksm -n flashcat
```

### 4.2 远程下发模式（kubeadm / 二进制手动部署均适用）

在 Flashcat 控制台 → 数据集成 → 数据采集 → 新建 Prometheus 采集任务，远程下发给 **Master 节点** 的 Node Agent（无需改组件监听地址）。配置见 [assets/examples/control-plane.toml](../../assets/examples/control-plane.toml)，粘贴前把每行 `cluster` 改成你的集群名。

验证（Master 节点本机执行）：

```bash
# apiserver
kubectl get --raw /metrics | head -20

# controller-manager / scheduler / etcd
curl -sk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  https://127.0.0.1:10257/metrics | head -20
curl -sk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  https://127.0.0.1:10259/metrics | head -20
curl -s http://127.0.0.1:2381/metrics | head -20
```

指标查询：

```text
apiserver_request_total
apiserver_request_duration_seconds
workqueue_queue_duration_seconds
scheduler_schedule_attempts_total
etcd_server_has_leader
```

## 5 验证

本 Chart 的资源名基于 Release 生成。Release 为 `categraf` 时主要资源如下：

```text
DaemonSet/categraf
StatefulSet/categraf-ksm
Deployment/categraf-operator
Deployment/categraf-kube-state-metrics
Service/categraf-kube-state-metrics
```

```bash
kubectl get pods -n flashcat -o wide
```

- Node Agent Pod 数 = 节点数
- KSM Agent、kube-state-metrics 各 1 个 Pod
- Flashcat 控制台能看到该集群指标（`cluster` 标签 = 集群名）

## 6 升级 / 回滚 / 卸载

```bash
# 升级
helm upgrade --install categraf ./categraf -n flashcat --create-namespace -f my-values.yaml

# 回滚
helm rollback categraf <REVISION> -n flashcat

# 卸载
helm uninstall categraf -n flashcat --wait
```

`operator.cleanup.nodeCategraf` 和 `operator.cleanup.ksmCategraf` 默认均为 `true`。卸载时会删除对应设备；如需保留设备，请在卸载前将对应开关改为 `false`。

> Flashcat 业务组不会被 Operator 自动删除，需要人工在控制台管理。
