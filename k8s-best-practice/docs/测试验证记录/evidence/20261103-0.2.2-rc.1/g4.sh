#!/usr/bin/env bash
# G4 配置面功能矩阵：逐个 helm upgrade + 运行时断言 + 复原基线
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/30-features.md"
VALS=/root/categraf-024-regression-values.yaml
PKG_REMOTE=/root/categraf-0.2.2-rc.1.tgz
EXTRA=/root/categraf-extra-scrape-values.yaml
RG=/root/categraf-rg-values.yaml
REV_REF=""

ev "$F" "G4 feature matrix：每例 apply -> assert -> restore（基线 values=${VALS}）"

upg() { # upg <label> [额外 helm 参数...]
  local label="$1"; shift
  {
    echo "## $label"
    echo '```'
    echo "\$ helm upgrade $REL $PKG_REMOTE -n $NS -f $VALS $*"
    ksi "helm upgrade $REL $PKG_REMOTE -n $NS -f $VALS $* --timeout 300s 2>&1 | tail -4"
    echo
    wait_ready
    echo '```'
  } >>"$F"
}
upg_f() { # upg_f <label> <额外 values 文件>
  local label="$1" vf="$2"
  {
    echo "## $label"
    echo '```'
    echo "\$ helm upgrade $REL $PKG_REMOTE -n $NS -f $VALS -f $vf"
    ksi "helm upgrade $REL $PKG_REMOTE -n $NS -f $VALS -f $vf --timeout 300s 2>&1 | tail -4"
    echo
    wait_ready
    echo '```'
  } >>"$F"
}
restore() { upg "恢复基线 values"; }
cm_node()   { ksi "kubectl -n $NS get cm categraf-config -o jsonpath='{.data.config\.toml}'"; }
cm_scrape() { ksi "kubectl -n $NS get cm categraf-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}'"; }
w2() { vmq "count(count_over_time($1[2m]))" | jq -r '.data.result[0].value[1] // "0"'; }
upval() { vmq "up{$1}" | jq -r '.data.result[0].value[1] // "absent"'; }
rev() { ksi "helm list -n $NS -o json" | jq -r '.[0].revision'; }

REV_REF=$(rev)

# =====================================================================
# 4.1 customLabels
# =====================================================================
upg "4.1 customLabels 新增 region=cn-shanghai（叠加 owner/environment）" --set categraf.customLabels.region=cn-shanghai
{
  echo "### 4.1 断言"
  echo '```'
  echo '--- node config.toml [global.labels] ---'
  cm_node | sed -n '/\[global.labels\]/,/^\[/p'
  echo '--- ksm scrape external_labels ---'
  cm_scrape | sed -n '1,12p'
  echo '--- 等待 45s 让设备心跳带上新标签 ---'
  sleep 45
  echo "VM: count_over_time({region=\"cn-shanghai\"}[2m]) = $(w2 '{region="cn-shanghai"}')"
  echo "设备标签:"
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")|\"  \(.ident) region=\(.tags_maps.region // \"-\")\""
  echo '```'
} >>"$F"
assert_eq "4.1-config 含 region" "1" "$(cm_node | grep -c 'region = "cn-shanghai"')"
assert_eq "4.1-scrape 含 region" "1" "$(cm_scrape | grep -c 'region: "cn-shanghai"')"
assert_ge "4.1-VM 指标含 region 标签" "1" "$(w2 '{region="cn-shanghai"}')"
assert_eq "4.1-设备标签含 region" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\" and .tags_maps.region==\"cn-shanghai\")]|length")"
restore
assert_eq "4.1-恢复后 config 无 region" "0" "$(cm_node | grep -c 'region = "cn-shanghai"')"

# =====================================================================
# 4.2 运行时参数：变更生效 + 触发滚动
# =====================================================================
BEFORE_POD=$(ksi "kubectl -n $NS get pods -l component=categraf --no-headers | head -1 | awk '{print \$1}'")
BEFORE_SUM=$(ksi "kubectl -n $NS get cm categraf-config -o jsonpath='{.metadata.annotations.checksum/config}'")
upg "4.2 运行时参数变更 interval=25/batch=4000/heartbeat=15/7000/3500" \
  --set categraf.config.interval=25 --set categraf.writer.batch=4000 \
  --set categraf.heartbeat.interval=15 --set categraf.heartbeat.timeout=7000 --set categraf.heartbeat.dialTimeout=3500
{
  echo "### 4.2 断言"
  echo '```'
  echo '--- 变更后 node config.toml（三段） ---'
  cm_node | grep -E '^\[global\]|^interval =|^\[writer_opt\]|^batch =|^chan_size =|^\[heartbeat\]|^timeout =|^dial_timeout ='
  echo "--- checksum/config 注解（变更前 ${BEFORE_SUM}） ---"
  ksi "kubectl -n $NS get cm categraf-config -o jsonpath='{.metadata.annotations.checksum/config}'; echo"
  echo "--- DS 是否滚动（pod 名/年龄） ---"
  ksi "kubectl -n $NS get pods -l component=categraf --no-headers"
  echo '```'
} >>"$F"
assert_eq "4.2-interval=25" "1" "$(cm_node | grep -c '^interval = 25')"
assert_eq "4.2-batch=4000" "1" "$(cm_node | grep -c '^batch = 4000')"
assert_eq "4.2-heartbeat interval=15" "1" "$(cm_node | grep -c '^interval = 15')"
restore
assert_eq "4.2-恢复后 interval=20" "1" "$(cm_node | grep -c '^interval = 20')"

# =====================================================================
# 4.4 extraScrapeConfigs（原生 scrape_config 扩展）
# =====================================================================
cat >/tmp/categraf-extra-scrape-values.yaml <<'YAML'
appMetrics:
  extraScrapeConfigs:
    - job_name: customer-custom-job
      kubernetes_sd_configs:
        - role: pod
          namespaces:
            names: [categraf]
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
          action: keep
          regex: annotated-metrics-test
        - source_labels: [__meta_kubernetes_pod_ip]
          target_label: __address__
          replacement: ${1}:8080
YAML
push /tmp/categraf-extra-scrape-values.yaml "$EXTRA"; rm -f /tmp/categraf-extra-scrape-values.yaml
upg_f "4.4 extraScrapeConfigs 注入 customer-custom-job" "$EXTRA"
{
  echo "### 4.4 断言"
  echo '```'
  echo '--- 渲染后的 job 列表 ---'
  cm_scrape | grep -nE 'job_name|namespaces|customer'
  echo '--- 等待 60s 后查 up ---'
  sleep 60
  echo "up{job=\"customer-custom-job\"} = $(upval 'job="customer-custom-job"')"
  vmq 'up{job="customer-custom-job"}' | jq -r '.data.result[]? | "  up=\(.value[1]) instance=\(.metric.instance) pod=\(.metric.pod // "-")"'
  echo '```'
} >>"$F"
assert_eq "4.4-config 含 customer-custom-job" "1" "$(cm_scrape | grep -c "job_name: 'customer-custom-job'")"
assert_ge "4.4-新 job target up" "1" "$(w2 'up{job="customer-custom-job"}')"
assert_eq "4.4-新 job up=1" "1" "$(upval 'job="customer-custom-job"')"
# 负向：非 list 配置必须被 helm 拒绝且不改变 release
REV_BEFORE=$(rev)
{
  echo "### 4.4-负向：extraScrapeConfigs 非 list 时 helm upgrade 必须失败且不改动 release"
  echo '```'
  echo "\$ helm upgrade ... --set appMetrics.extraScrapeConfigs=notalist"
  ksi "helm upgrade $REL $PKG_REMOTE -n $NS -f $VALS --set appMetrics.extraScrapeConfigs=notalist --timeout 120s 2>&1 | tail -3; echo EXIT=\$?"
  echo "升级前 revision=${REV_BEFORE}，升级后 revision=$(rev)"
  echo '```'
} >>"$F"
assert_eq "4.4-负向不改变 revision" "$REV_BEFORE" "$(rev)"
restore
assert_eq "4.4-恢复后无 customer-custom-job" "0" "$(cm_scrape | grep -c 'customer-custom-job')"

# =====================================================================
# 4.3 annotation 自动发现：改坏 path 证明 relabel 真正生效
# =====================================================================
{
  echo "## 4.3 annotation 自动发现（prometheus.io/path 生效性）"
  echo '```'
  echo '--- 修改前 ---'
  echo "up{job=\"app-metrics\"} = $(upval 'job="app-metrics"')"
  vmq 'up{job="app-metrics"}' | jq -r '.data.result[]? | "  up=\(.value[1]) instance=\(.metric.instance) service=\(.metric.service // "-") team=\(.metric.team // "-") pod=\(.metric.pod // "-") namespace=\(.metric.namespace // "-")"'
  echo
  echo "\$ kubectl patch deploy annotated-metrics-test（prometheus.io/path=/metrics-broken）"
  ksi "kubectl -n $NS patch deploy annotated-metrics-test --type merge -p '{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"prometheus.io/path\":\"/metrics-broken\"}}}}}'"
  ksi "kubectl -n $NS rollout status deploy/annotated-metrics-test --timeout=120s"
  echo '--- 等待 90s ---'
  sleep 90
  echo "up{job=\"app-metrics\"} = $(upval 'job="app-metrics"')"
  echo
  echo "\$ 恢复 annotation prometheus.io/path=/metrics"
  ksi "kubectl -n $NS patch deploy annotated-metrics-test --type merge -p '{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"prometheus.io/path\":\"/metrics\"}}}}}'"
  ksi "kubectl -n $NS rollout status deploy/annotated-metrics-test --timeout=120s"
  echo '--- 等待 45s ---'
  sleep 45
  echo "up{job=\"app-metrics\"} = $(upval 'job="app-metrics"')"
  echo '```'
} >>"$F"
assert_eq "4.3-改坏 path 后 target down" "0" "$(upval 'job="app-metrics"')"
sleep 45
assert_eq "4.3-恢复 path 后 target up" "1" "$(upval 'job="app-metrics"')"

# =====================================================================
# 4.11 Node Agent inputs 组合关闭
# =====================================================================
upg "4.11 inputs：cadvisor=false + nodeExporter=false + hostNative.disk=false" \
  --set nodeCategraf.inputs.cadvisor=false --set nodeCategraf.inputs.nodeExporter=false --set nodeCategraf.inputs.hostNative.disk=false
{
  echo "### 4.11 断言"
  echo '```'
  echo '--- ConfigMap 清单（cadvisor/node-exporter/disk 输入应消失或替换为空目录）---'
  ksi "kubectl -n $NS get cm | grep -E 'input|disable'"
  echo '--- Node Agent volumeMounts ---'
  ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}' | tr ' ' '\n' | grep -E 'input|categraf/conf'"
  echo '--- 等待 150s 后指标 ---'
  sleep 150
  echo "count_over_time(up{job=\"kubelet\"}[2m])      = $(w2 'up{job="kubelet"}')"
  echo "count_over_time(node_cpu_seconds_total[2m])   = $(w2 'node_cpu_seconds_total')"
  echo "count_over_time(disk_used[2m])                = $(w2 'disk_used')"
  echo '```'
} >>"$F"
assert_eq "4.11-cadvisor关闭后 up{job=kubelet} 消失" "0" "$(w2 'up{job="kubelet"}')"
assert_eq "4.11-nodeExporter关闭后 node_cpu 消失" "0" "$(w2 'node_cpu_seconds_total')"
assert_eq "4.11-hostNative.disk 关闭后 disk_used 消失" "0" "$(w2 'disk_used')"
restore
sleep 90
assert_ge "4.11-恢复后 node_cpu 回来" "1" "$(w2 'node_cpu_seconds_total')"
assert_ge "4.11-恢复后 disk_used 回来" "1" "$(w2 'disk_used')"
assert_ge "4.11-恢复后 up{job=kubelet} 回来" "1" "$(w2 'up{job="kubelet"}')"

# =====================================================================
# 4.5/4.6/4.7/4.8/4.9/4.10 组件与 job 开关组合
# =====================================================================
upg "4.5-4.10 组件组合：KSM部署关? 否；KS 指标 job 关；coreDns/kubeProxy/networkPlugin 关；controlPlane 开" \
  --set ksmCategraf.jobs.kubeStateMetrics=false \
  --set coreDns.enabled=false --set kubeProxy.enabled=false \
  --set networkPlugin.calico.enabled=false --set networkPlugin.cilium.enabled=false \
  --set controlPlane.enabled=true
{
  echo "### 4.5-4.10 断言"
  echo '```'
  echo '--- scrape job 列表 ---'
  cm_scrape | grep -nE "job_name"
  echo '--- node config 中 kube-proxy 输入相关 volumeMount ---'
  ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}' | tr ' ' '\n' | grep -c 'kube-proxy' || true"
  echo '--- 等待 150s 后 up 指标 ---'
  sleep 150
  for j in coredns kube-proxy kube-state-metrics apiserver kube-controller-manager kube-scheduler etcd calico cilium; do
    printf '  up{%s} = %s  (2m 内 series 数=%s)\n' "$j" "$(upval "job=\"$j\"")" "$(w2 "up{job=\"$j\"}")"
  done
  echo '--- 控制平面 job 渲染详情 ---'
  cm_scrape | grep -A6 -E "job_name: '(apiserver|kube-controller-manager|kube-scheduler|etcd)'" | grep -E 'job_name|replacement|regex' | head -20
  echo '```'
} >>"$F"
assert_eq "4.6-jobs.kubeStateMetrics=false 移除 job" "0" "$(cm_scrape | grep -c "job_name: 'kube-state-metrics'")"
assert_eq "4.7-coreDns=false 移除 job" "0" "$(cm_scrape | grep -c "job_name: 'coredns'")"
assert_eq "4.8-networkPlugin=false 移除 job" "0" "$(cm_scrape | grep -cE "job_name: '(calico|cilium)'")"
assert_eq "4.9-kubeProxy=false 移除输入挂载" "0" "$(ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'" | grep -c 'kube-proxy')"
assert_eq "4.10-controlPlane=true 渲染 4 个 job" "4" "$(cm_scrape | grep -cE "job_name: '(apiserver|kube-controller-manager|kube-scheduler|etcd)'")"
assert_eq "4.7-运行时 up{job=coredns} 消失" "0" "$(w2 'up{job="coredns"}')"
assert_eq "4.9-运行时 up{job=kube-proxy} 消失" "0" "$(w2 'up{job="kube-proxy"}')"
assert_eq "4.6-运行时 up{job=kube-state-metrics} 消失" "0" "$(w2 'up{job="kube-state-metrics"}')"
# 控制平面：apiserver 应可达；其余受 master 监听 127.0.0.1 限制
APISERVER_UP=$(upval 'job="apiserver"')
assert_eq "4.10-apiserver 可采集" "1" "$APISERVER_UP"
restore
sleep 120
assert_ge "4.7-恢复后 coredns up" "1" "$(w2 'up{job="coredns"}')"
assert_ge "4.9-恢复后 kube-proxy up" "1" "$(w2 'up{job="kube-proxy"}')"
assert_ge "4.6-恢复后 kube-state-metrics up" "1" "$(w2 'up{job="kube-state-metrics"}')"

# =====================================================================
# 4.5 kubeStateMetrics.enabled=false（部署级）
# =====================================================================
upg "4.5 kubeStateMetrics.enabled=false（移除 KSM Deployment/Service）" --set kubeStateMetrics.enabled=false
{
  echo "### 4.5 断言"
  echo '```'
  echo '--- Deployment/Service 是否消失 ---'
  ksi "kubectl -n $NS get deploy,svc | grep -E 'kube-state-metrics' || echo '(KSM Deployment/Service 已移除)'"
  echo '--- 等待 150s 后 kube_* 指标 ---'
  sleep 150
  echo "count_over_time(kube_pod_info[2m]) = $(w2 'kube_pod_info')"
  echo "count_over_time(kube_node_info[2m]) = $(w2 'kube_node_info')"
  echo "up{job=\"kube-state-metrics\"} = $(upval 'job="kube-state-metrics"')"
  echo '```'
} >>"$F"
assert_eq "4.5-KSM Deployment 消失" "0" "$(ksi "kubectl -n $NS get deploy -o name" | grep -c 'kube-state-metrics')"
assert_eq "4.5-kube_pod_info 停止" "0" "$(w2 'kube_pod_info')"
restore
sleep 180
assert_ge "4.5-恢复后 kube_pod_info 回来" "1" "$(w2 'kube_pod_info')"

# =====================================================================
# 4.12 hostExec 关闭 + privileged=false
# =====================================================================
upg "4.12 hostExec.enabled=false + securityContext.privileged=false" \
  --set nodeCategraf.hostExec.enabled=false --set nodeCategraf.securityContext.privileged=false
{
  echo "### 4.12 断言"
  echo '```'
  echo '--- pod securityContext ---'
  ksi "kubectl -n $NS get pods -l component=categraf -o jsonpath='{.items[0].spec.containers[0].securityContext}'; echo"
  echo '--- env CATEGRAF_HOST_EXEC_PROFILE ---'
  ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].env}' | tr ',' '\n' | grep -A1 HOST_EXEC"
  echo '--- 是否还挂载 ibex ---'
  ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.volumes[*].name}' | tr ' ' '\n' | grep -c ibex || true"
  echo '--- 受限模式仍能采集（等待 60s）---'
  sleep 60
  echo "count_over_time(node_cpu_seconds_total[2m]) = $(w2 'node_cpu_seconds_total')"
  echo "up{job=\"kubelet\"} = $(upval 'job="kubelet"')"
  echo '```'
} >>"$F"
assert_eq "4.12-不再挂载 ibex" "0" "$(ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.volumes[*].name}'" | grep -c ibex)"
assert_eq "4.12-HOST_EXEC_PROFILE=false" "false" "$(ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"CATEGRAF_HOST_EXEC_PROFILE\")].value}'")"
assert_ge "4.12-受限模式仍采集 node 指标" "1" "$(w2 'node_cpu_seconds_total')"
restore
sleep 60

# =====================================================================
# 4.14 operator.enabled=false
# =====================================================================
upg "4.14 operator.enabled=false（移除 Operator 及其资源）" --set operator.enabled=false
{
  echo "### 4.14 断言"
  echo '```'
  echo '--- operator 资源 ---'
  ksi "kubectl -n $NS get deploy,sa,cm 2>/dev/null | grep -E 'operator' || echo '(operator 资源已移除)'"
  echo '--- 设备仍在线（agent 不受影响）---'
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")|\"  \(.ident) target_up=\(.target_up)\""
  echo '```'
} >>"$F"
assert_eq "4.14-operator Deployment 消失" "0" "$(ksi "kubectl -n $NS get deploy -o name" | grep -c operator)"
assert_eq "4.14-设备仍为 3" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
restore

# =====================================================================
# 4.15 RBAC 最小权限
# =====================================================================
R="$EV/31-rbac.md"
ev "$R" "G4.15 RBAC 最小权限：operator / node-agent / ksm-agent 三个 SA 的 can-i 断言"
{
  echo '## operator SA'
  echo '```'
  for q in "get nodes" "list nodes" "get daemonsets.apps -n categraf" "create leases.coordination.k8s.io -n categraf" "list pods -n categraf" "create secrets -n categraf"; do
    printf '  %-46s ' "$q"
    ksi "kubectl auth can-i $q --as=system:serviceaccount:categraf:categraf-operator --namespace=categraf 2>&1"
  done
  echo '```'
  echo '## node-agent SA（categraf）'
  echo '```'
  for q in "list pods" "get nodes/metrics" "get nodes/stats" "get nodes/proxy" "list endpointslices.discovery.k8s.io" "get /metrics" "create secrets -n categraf"; do
    printf '  %-46s ' "$q"
    ksi "kubectl auth can-i $q --as=system:serviceaccount:categraf:categraf --namespace=categraf 2>&1"
  done
  echo '```'
} >>"$R"
assert_eq "4.15-operator 可 list nodes" "yes" "$(ksi "kubectl auth can-i list nodes --as=system:serviceaccount:categraf:categraf-operator 2>/dev/null")"
assert_eq "4.15-operator 可 create leases" "yes" "$(ksi "kubectl auth can-i create leases.coordination.k8s.io -n categraf --as=system:serviceaccount:categraf:categraf-operator 2>/dev/null")"
assert_eq "4.15-operator 不可 create secrets" "no" "$(ksi "kubectl auth can-i create secrets -n categraf --as=system:serviceaccount:categraf:categraf-operator 2>/dev/null")"
assert_eq "4.15-node-agent 可 list pods" "yes" "$(ksi "kubectl auth can-i list pods --as=system:serviceaccount:categraf:categraf 2>/dev/null")"
assert_eq "4.15-node-agent 可 get nodes/metrics" "yes" "$(ksi "kubectl auth can-i get nodes/metrics --as=system:serviceaccount:categraf:categraf 2>/dev/null")"
assert_eq "4.15-node-agent 不可 create secrets" "no" "$(ksi "kubectl auth can-i create secrets -n categraf --as=system:serviceaccount:categraf:categraf 2>/dev/null")"

# =====================================================================
# 4.13 多 Release 隔离（独立 namespace + 独立 clusterName + ident 模板）
# =====================================================================
TOKEN=$(security find-generic-password -s flashcat-test-token -a test -w)
cat >/tmp/categraf-rg-values.yaml <<YAML
categraf:
  clusterName: k8s-flashcat-test-20261029-rg
  customLabels:
    environment: test
    owner: platform
nodeCategraf:
  hostname: "\${cluster}-\$hostname"
ksmCategraf:
  enabled: true
operator:
  enabled: true
  userToken: "$TOKEN"
YAML
push /tmp/categraf-rg-values.yaml "$RG"; rm -f /tmp/categraf-rg-values.yaml
{
  echo "## 4.13 多 Release 隔离（ns=categraf-rg，clusterName=k8s-flashcat-test-20261029-rg）"
  echo '```'
  echo "\$ helm upgrade --install categraf-rg $PKG_REMOTE -n categraf-rg --create-namespace -f $VALS -f $RG"
  ksi "helm upgrade --install categraf-rg $PKG_REMOTE -n categraf-rg --create-namespace -f $VALS -f $RG --timeout 300s 2>&1 | tail -6"
  echo
  echo '$ 工作负载与资源命名（不应与主 release 冲突）'
  ksi "kubectl -n categraf-rg get ds,sts,deploy,cm -o name | head -20"
  echo
  echo '$ ClusterRole 命名隔离'
  ksi "kubectl get clusterrole 2>/dev/null | grep -E 'categraf(-rg)?-' | head -10"
  echo
  echo '$ 等待 60s 后设备（集群标签隔离 + ident 模板）'
  sleep 60
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r '.dat.list[] | select(.tags_maps.cluster|test("rg$")) | "  \(.ident) cluster=\(.tags_maps.cluster) target_up=\(.target_up)"'
  echo
  echo '$ 主 release 设备不受影响'
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")|\"  \(.ident) cluster=\(.tags_maps.cluster) target_up=\(.target_up)\""
  echo '```'
} >>"$F"
assert_eq "4.13-独立 release 设备数" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster|test(\"rg$\"))]|length")"
assert_eq "4.13-ident 模板生效(含 -rg-)" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster|test(\"rg$\"))|select(.ident|contains(\"-rg-\"))]|length")"
assert_eq "4.13-主集群设备仍为 3" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"

# 卸载 rg release：其 operator cleanup hook 应只删自己的设备
{
  echo "### 4.13 卸载 categraf-rg：cleanup hook 只删本集群设备"
  echo '```'
  ksi "helm uninstall categraf-rg -n categraf-rg --timeout 600s 2>&1 | tail -4"
  sleep 20
  echo 'uninstall 后：'
  echo "  rg 设备数 = $(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster|test(\"rg$\"))]|length")"
  echo "  主集群设备数 = $(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
  echo '```'
} >>"$F"
sleep 30
assert_eq "4.13-rg 卸载后本集群设备清理" "0" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster|test(\"rg$\"))]|length")"
assert_eq "4.13-rg 卸载不影响主集群设备" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
ksi "kubectl delete namespace categraf-rg --timeout=180s 2>&1 | tail -2" >>"$F" 2>&1

# =====================================================================
# 收尾：最终状态确认
# =====================================================================
{
  echo "## 收尾：最终状态（应为基线 values 的 rc.1）"
  echo '```'
  ksi "helm list -n $NS; echo; kubectl -n $NS get pods -o wide | head -8"
  echo "设备: $(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")|select(.target_up==2)]|length")/3 target_up=2"
  echo "up 全为 1: $(vmq "up{cluster=\"$CLUSTER\"}" | jq '[.data.result[]|select(.value[1]!="1")]|length') 条异常"
  echo '```'
} >>"$F"

echo "G4 完成: $F"
echo "PASS=$(grep -c PASS "$EV/results.tsv")  FAIL=$(grep -c FAIL "$EV/results.tsv" || true)"
grep FAIL "$EV/results.tsv" || echo "无 FAIL"
