# CMD: G1 开关矩阵：每个开关关闭/开启时的资源增减
# AT: 2026-11-03T05:09:06Z / 2026-11-03T13:09:06+0800

默认渲染资源清单：
```
   3 kind: ClusterRole
   3 kind: ClusterRoleBinding
  19 kind: ConfigMap
   1 kind: DaemonSet
   2 kind: Deployment
   1 kind: Job
   1 kind: Role
   1 kind: RoleBinding
   1 kind: Secret
   1 kind: Service
   4 kind: ServiceAccount
   1 kind: StatefulSet
```

### 默认-DaemonSet -> 匹配 /^kind: DaemonSet/ = 1 (期望 1: 默认安装 node agent)
### 默认-StatefulSet -> 匹配 /^kind: StatefulSet/ = 1 (期望 1: 默认安装 ksm agent)
### 默认-Deployment -> 匹配 /^kind: Deployment/ = 2 (期望 2: kube-state-metrics + operator)
### nodeAgent-off-DS -> 匹配 /^kind: DaemonSet/ = 0 (期望 0: nodeCategraf.enabled=false 不产生 DaemonSet)
### nodeAgent-off-config -> 匹配 /name: t-config$/ = 0 (期望 0: 对应 configmap 也消失)
### ksmAgent-off-STS -> 匹配 /^kind: StatefulSet/ = 0 (期望 0: ksmCategraf.enabled=false 不产生 StatefulSet)
### ksm-off-appMetrics-job -> 匹配 /job_name: 'app-metrics'/ = 0 (期望 0: ksm 关闭时 app-metrics job 随之消失)
### ksm-off-coreDns-job -> 匹配 /job_name: 'coredns'/ = 0 (期望 0: ksm 关闭时 coredns job 随之消失)
### ksm-metrics-job-off -> 匹配 /job_name: 'kube-state-metrics'/ = 0 (期望 0: jobs.kubeStateMetrics=false 移除 KSM job)
### ksm-off -> 匹配 /name: t-kube-state-metrics$/ = 0 (期望 0: kubeStateMetrics.enabled=false 移除 Deployment/Service)
### operator-off -> 匹配 /name: t-operator$/ = 0 (期望 0: operator.enabled=false 不产生 operator 资源)
### operator-cleanup-hook -> 匹配 /helm.sh/hook": pre-delete/ = 4 (期望 4: cleanup 两开关均 true 时 4 个 hook 资源带 pre-delete)
### operator-cleanup-off -> 匹配 /kind: Job/ = 0 (期望 0: cleanup 均 false 时无 hook Job)
### appMetrics-off -> 匹配 /job_name: 'app-metrics'/ = 0 (期望 0: appMetrics.enabled=false 无 app-metrics job)
### coreDns-off -> 匹配 /job_name: 'coredns'/ = 0 (期望 0: coreDns.enabled=false 无 coredns job)
### kubeProxy-off -> 匹配 /input.prometheus/kube-proxy.toml/ = 0 (期望 0: kubeProxy.enabled=false 无 kube-proxy 输入)
### networkPlugin-off -> 匹配 /job_name: .(calico|cilium)./ = 0 (期望 0: calico/cilium 都关则无对应 job)
### controlPlane-on -> 匹配 /job_name: .(apiserver|kube-controller-manager|kube-scheduler|etcd)./ = 4 (期望 4: controlPlane.enabled=true 增加 4 个控制平面 job)
### cadvisor-off -> 匹配 /input.prometheus/cadvisor.toml/ = 0 (期望 0: inputs.cadvisor=false 去掉 cadvisor 输入)
### nodeExporter-off -> 匹配 /categraf-input-node-exporter/ = 0 (期望 0: inputs.nodeExporter=false 去掉 node_exporter 输入)
### hostExec-off -> 匹配 /name: ibex-host-meta/ = 0 (期望 0: hostExec.enabled=false 不挂 ibex)
