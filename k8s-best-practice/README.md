# K8S 监控采集最佳实践

本仓库按以下三层结构组织 K8S 监控采集方案：

1. [K8S 基础监控](#1-k8s-基础监控)
2. [K8S 组件监控（自建 K8S 集群）](#2-k8s-组件监控自建-k8s-集群)
3. [K8S 应用监控](#3-k8s-应用监控)

---

## 1、K8S 基础监控

### 1.1 K8S 指标监控采集（Helm 版本，推荐）

- **文档**：[`docs/01-k8s-base/K8S指标监控.md`](docs/01-k8s-base/K8S指标监控.md)
- **一键部署组件**：
  - `Kube-State-Metrics`（Deployment）：采集 K8s 对象状态指标
  - `KSM Agent`（StatefulSet）：从 KSM 拉取指标并写入 Flashcat；内置 annotation 应用发现任务，并支持通过原生 `extraScrapeConfigs` 扩展
  - `Node Agent`（DaemonSet）：每节点采集 cAdvisor / kubelet / 主机指标
  - `Operator`（Deployment，可选）：节点删除后自动清理 Flashcat 残留设备
- **部署方式**：OCI 在线部署 / 离线部署 / values 文件部署
- **Chart 仓库**：`oci://registry.flashcat.cloud/public/charts/categraf:0.2.x`
  - 生产版本 `0.2.3`（`latest` 指向它，2026-11-16 发布）；上一版 `0.2.2` 保留可回退
  - 版本号规则见 [`docs/附录/发布Chart到仓库.md`](docs/附录/发布Chart到仓库.md)

### 1.2 K8S 日志采集（节点和容器日志）

- **文档**：[`docs/01-k8s-base/K8S日志采集.md`](docs/01-k8s-base/K8S日志采集.md)

| 日志类型 | 负责方 | 采集方式 |
|---|---|---|
| 节点操作系统日志（syslog/messages） | K8s 运维 | DaemonSet log 插件，控制台远程下发 |
| 容器 stdout/stderr | K8s 运维 | DaemonSet 自动发现 + 控制台创建采集任务 |
| 容器文件日志 | 应用运维 | 修改工作负载，添加 Categraf sidecar |

---

## 2、K8S 组件监控（自建 K8S 集群）

- **文档**：[`docs/01-k8s-base/K8S指标监控.md`](docs/01-k8s-base/K8S指标监控.md) 第 4 章「自建集群组件监控补充」
- **覆盖组件**：CoreDNS、kube-proxy、Calico / Cilium、控制平面（apiserver / kube-controller-manager / kube-scheduler / etcd）
- **采集方式**：组件采集已集成到 Helm Chart，在 `my-values.yaml` 中开启对应开关即可；控制平面可用自动发现模式（仅 kubeadm 集群）或远程下发模式（kubeadm / 二进制手动部署均适用）

---

## 3、K8S 应用监控

### 3.1 应用监控采集

- **文档**：[`docs/03-k8s-app/应用监控采集.md`](docs/03-k8s-app/应用监控采集.md)
- 应用暴露 Prometheus 指标端点，Categraf 采集。

| 应用类型 | 暴露方式 | 指标路径 |
|---|---|---|
| 通用应用（Go/Python/Node.js） | Prometheus client | `/metrics` |
| Spring Boot | Micrometer + Prometheus | `/actuator/prometheus` |
| 非 Spring Boot Java 应用 | JMX Exporter Agent | `/metrics`（默认 8089 端口） |
| 中间件/数据库 | Exporter Sidecar/Deployment | 按 Exporter 而定，如 Redis 9121 |
| OTel 场景 | OTel JMX 扩展 | 无需 Categraf，直接上报 |

- **采集配置**：Flashcat 控制台手动下发 或 自动发现（推荐）
- **标签规范**：抓取参数使用 `prometheus.io/scrape|port|path|scheme` annotation；身份与聚合使用 `env`、`cluster`、`namespace`、`service`、`job`、`team`
- **示例配置**：[`assets/examples/`](assets/examples/)

### 3.2 应用 APM 接入

- **文档**：[`docs/03-k8s-app/应用APM接入.md`](docs/03-k8s-app/应用APM接入.md)
- 新项目可统一接入 OTel，实现 Trace + Metrics 统一采集。

---

## 附录

| 文档/目录 | 用途 |
|---|---|
| [`assets/categraf-helm/categraf-operator/README.md`](assets/categraf-helm/categraf-operator/README.md) | categraf-operator：K8s 节点删除后清理 Flashcat 残留设备 |
| [`docs/附录/idaas.md`](docs/附录/idaas.md) | Flashcat 对接阿里云 IDaaS 单点登录配置 |
| [`docs/附录/发布Chart到仓库.md`](docs/附录/发布Chart到仓库.md) | categraf chart 推送 OCI 仓库的固定地址与命令（`oci://registry.flashcat.cloud/public/charts`） |
| [`publish-chart.sh`](publish-chart.sh) | 一键推送 categraf chart 到 OCI 仓库 |
| [`docs/页面设计/K8S接入Categraf页面设计.md`](docs/页面设计/K8S接入Categraf页面设计.md) | 控制台「接入 Kubernetes」页面的内容设计（DaemonSet / StatefulSet 两套 8 节内容、变量注入矩阵、Helm `latest` 策略） |
| [`docs/页面设计/K8s接入Categraf-页面demo.html`](docs/页面设计/K8s接入Categraf-页面demo.html) | 配置页 Demo：填参数 → 实时生成 values.yaml → 部署命令 + 接入校验（浏览器直接打开） |
| [`docs/页面设计/K8s接入Categraf-前端交付说明.md`](docs/页面设计/K8s接入Categraf-前端交付说明.md) | 给前端的交付说明：参数契约、values/命令生成规则、交互与验收标准 |
| [`assets/opentelemetry-java-instrumentation-main/`](assets/opentelemetry-java-instrumentation-main/) | OTel Java Instrumentation 参考源码 |
| [`archive/`](archive/) | 合并前的原始文档存档 |
