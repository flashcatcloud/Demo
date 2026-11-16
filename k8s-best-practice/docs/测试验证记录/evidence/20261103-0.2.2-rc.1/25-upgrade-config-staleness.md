# CMD: G3 补充：0.2.1→rc.1 升级后配置是否生效（找出 app-metrics 缺失 / customLabels 缺失 / syslog 报错的根因）
# AT: 2026-11-03T05:27:43Z / 2026-11-03T13:27:43+0800

## A. 升级后 Pod 内实际挂载的配置 vs ConfigMap
```
node pod=categraf-4mbzq  ksm pod=categraf-ksm-0
--- pod 创建/启动时间 ---
categraf-4mbzq                                 Running   2026-11-03T05:22:16Z
categraf-dbw8m                                 Running   2026-11-03T05:22:16Z
categraf-ksm-0                                 Running   2026-11-03T05:22:16Z
categraf-kube-state-metrics-844f8d85fb-pn7w7   Running   2026-11-03T05:22:16Z
categraf-operator-7c89787646-hd4mr             Running   2026-11-03T05:22:16Z
--- ConfigMap 中 node config.toml（新）---
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029"
categraf = "nodeAgent"
environment = "test"
owner = "platform"

[global.n9e_server]
--- Pod 内挂载的 config.toml（实际生效）---
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029"
categraf = "nodeAgent"
[global.n9e_server]
--- KSM Pod 内挂载的 scrape 配置是否含 metrics_path 修复 ---
6:  - job_name: 'kube-state-metrics'
13:  - job_name: 'app-metrics'
26:        target_label: __metrics_path__
35:  - job_name: 'coredns'
42:  - job_name: 'calico'
53:  - job_name: 'cilium'
```
## B. syslog 报错来源（input.syslog 已挂空目录但仍在报错）
```
--- pod 内 conf 目录 ---
total 12
drwxrwxrwx  3 root root 4096 Nov  3 13:22 .
drwxr-xr-x 15 root root 4096 Nov  3 13:22 ..
drwxr-xr-x  2 root root 4096 Nov  3 13:22 ..2026_11_03_05_22_16.2390397250
lrwxrwxrwx  1 root root   32 Nov  3 13:22 ..data -> ..2026_11_03_05_22_16.2390397250
---
config.toml
input.cpu
input.disk
input.diskio
input.kernel
input.mem
input.net
input.netstat
input.node_exporter
input.processes
input.prometheus
input.swap
input.syslog
input.system
--- 镜像内所有 syslog 相关文件 ---
/opt/categraf/conf/input.syslog
/sys/kernel/btf/nf_log_syslog
/sys/module/nf_log_syslog
/hostfs/etc/rsyslog.d
/hostfs/etc/apparmor.d/usr.sbin.rsyslogd
/hostfs/etc/rsyslog.conf
/hostfs/etc/logrotate.d/rsyslog
/hostfs/usr/sbin/rsyslogd
/hostfs/usr/lib/rsyslog
/hostfs/usr/share/rsyslog
/hostfs/usr/include/syslog.h
/hostfs/var/log/syslog.4.gz
/hostfs/var/log/syslog
/hostfs/var/log/syslog.2.gz
/hostfs/var/log/syslog.1
/hostfs/var/log/syslog.3.gz
/hostfs/var/spool/rsyslog
/hostfs/sys/module/nf_log_syslog
--- pod 内进程 ---
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.1  0.1 166828 12248 ?        Ss   11:12   0:09 /sbin/init
root           2  0.0  0.0      0     0 ?        S    11:12   0:00 [kthreadd]
root           3  0.0  0.0      0     0 ?        I<   11:12   0:00 [rcu_gp]
root           4  0.0  0.0      0     0 ?        I<   11:12   0:00 [rcu_par_gp]
root           5  0.0  0.0      0     0 ?        I<   11:12   0:00 [slub_flushwq]
root           6  0.0  0.0      0     0 ?        I<   11:12   0:00 [netns]
root           8  0.0  0.0      0     0 ?        I<   11:12   0:00 [kworker/0:0H-events_highpri]
root          10  0.0  0.0      0     0 ?        I<   11:12   0:00 [mm_percpu_wq]
root          11  0.0  0.0      0     0 ?        S    11:12   0:00 [rcu_tasks_rude_]
--- 当前容器 syslog 报错计数（最近 500 行）---
34
```
daemonset.apps/categraf restarted
statefulset.apps/categraf-ksm restarted
Waiting for daemon set "categraf" rollout to finish: 0 out of 2 new pods have been updated...
Waiting for daemon set "categraf" rollout to finish: 1 out of 2 new pods have been updated...
Waiting for daemon set "categraf" rollout to finish: 1 out of 2 new pods have been updated...
Waiting for daemon set "categraf" rollout to finish: 1 out of 2 new pods have been updated...
Waiting for daemon set "categraf" rollout to finish: 1 of 2 updated pods are available...
daemon set "categraf" successfully rolled out
partitioned roll out complete: 1 new pods have been updated...
## C. 强制滚动重启后的状态
```
新 node pod=categraf-ml6qg
--- 新 Pod 内 config.toml 是否含 customLabels ---
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029"
categraf = "nodeAgent"
environment = "test"
owner = "platform"

[global.n9e_server]
--- VM: customLabels 是否出现在指标上 ---
count({owner="platform"}) = 13326
count({environment="test"}) = 13326
--- VM: app-metrics target ---
up{job="app-metrics"} = 1
--- syslog 报错是否消失 ---
10
```
## D. syslog 根因补充排查
```
--- conf 目录里是否还有 syslog 配置 ---
---
/opt/categraf
/opt/categraf/conf
/opt/categraf/conf/input.mem
/opt/categraf/conf/input.swap
/opt/categraf/conf/input.system
/opt/categraf/conf/input.prometheus
/opt/categraf/conf/input.syslog
/opt/categraf/conf/input.syslog/..2026_11_03_05_27_46.2153566933
/opt/categraf/conf/input.processes
/opt/categraf/conf/input.net
/opt/categraf/conf/input.disk
/opt/categraf/conf/input.netstat
/opt/categraf/conf/input.kernel
/opt/categraf/conf/input.node_exporter
/opt/categraf/conf/input.node_exporter/..2026_11_03_05_27_46.2413670382
/opt/categraf/conf/input.cpu
/opt/categraf/conf/input.diskio
--- config.toml 全文（node） ---
[global]
print_configs = false
hostname = "${HOSTNAME}"
omit_hostname = false
precision = "ms"
interval = 20
providers = ["local", "http", "rmq"]
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029"
categraf = "nodeAgent"
environment = "test"
owner = "platform"

[global.n9e_server]
address="http://flashcat.local:19000"
[writer_opt]
batch = 3000
chan_size = 1500000
[heartbeat]
enable = true
url = "http://flashcat.local:19000/v1/n9e-plus/heartbeat?gid=2"
interval = 12
timeout = 6000
dial_timeout = 3000
--- 镜像里 tail 是否存在 ---
/usr/bin/tail
-rwxr-xr-x 1 root root 64032 Jan 23  2026 /bin/tail
-rwxr-xr-x 1 root root 64032 Jan 23  2026 /usr/bin/tail
```
