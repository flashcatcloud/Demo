# CMD: G1 资源约定断言（命名/镜像/权限/挂载）
# AT: 2026-11-03T07:22:12Z / 2026-11-03T15:22:12+0800

## 默认渲染中的关键约定
```
--- 资源名 ---
              name: t-operator-secret
            name: t-ksm-config
            name: t-ksm-scrape
            name: t-operator-config
          name: t-config
          name: t-disable-host
          name: t-disable-syslog
          name: t-input-cadvisor
          name: t-input-cpu
          name: t-input-disk
          name: t-input-diskio
          name: t-input-kernel
          name: t-input-kube-proxy
          name: t-input-mem
          name: t-input-net
          name: t-input-netstat
          name: t-input-node-exporter
          name: t-input-process
          name: t-input-swap
          name: t-input-system
    name: t-kube-state-metrics
  name: t-config
  name: t-default-kube-state-metrics
  name: t-default-node-agent
  name: t-default-operator
  name: t-disable-host
  name: t-disable-syslog
  name: t-input-cadvisor
  name: t-input-cpu
  name: t-input-disk
--- 镜像 ---
        - image: "registry.flashcat.cloud/public/categraf_ent:v0.5.32"
        - image: "registry.flashcat.cloud/public/kube-state-metrics/kube-state-metrics:v2.19.1"
        image: "registry.flashcat.cloud/public/categraf-operator:0.0.7"
        image: "registry.flashcat.cloud/public/categraf_ent:servicemap-v0.5.32"
--- ClusterRole 名 ---
  name: t-default-kube-state-metrics
  name: t-default-operator
  name: t-default-node-agent
  name: t-default-kube-state-metrics
  name: t-default-operator
  name: t-default-node-agent
--- selector / instance 标签 ---
48
--- hostNetwork/hostPID ---
2
--- hostfs 挂载 ---
1
--- syslog 禁用 configmap ---
4
```
