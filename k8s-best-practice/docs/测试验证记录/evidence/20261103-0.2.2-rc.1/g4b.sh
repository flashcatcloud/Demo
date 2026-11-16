#!/usr/bin/env bash
# G4(lean) 配置面功能矩阵：合并独立用例，减少 helm 升级轮次与等待
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/30-features.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.1.tgz
EXTRA=/root/categraf-extra-scrape-values.yaml
RG=/root/categraf-rg-values.yaml

ev "$F" "G4(lean) feature matrix：合并独立用例，每例 apply->assert->restore；基线 values=$VALS"

upg() { local label="$1"; shift
  { echo "## $label"; echo '```'; echo "\$ helm upgrade $REL $PKG -n $NS -f $VALS $*";
    ksi "helm upgrade $REL $PKG -n $NS -f $VALS $* --timeout 240s 2>&1 | tail -3"; echo '```'; } >>"$F"
  wait_ready >/dev/null 2>&1
}
upg_f() { local label="$1" vf="$2"
  { echo "## $label"; echo '```'; echo "\$ helm upgrade $REL $PKG -n $NS -f $VALS -f $vf";
    ksi "helm upgrade $REL $PKG -n $NS -f $VALS -f $vf --timeout 240s 2>&1 | tail -3"; echo '```'; } >>"$F"
  wait_ready >/dev/null 2>&1
}
restore() { upg "恢复基线 values"; }
cm_node()   { ksi "kubectl -n $NS get cm categraf-config -o jsonpath='{.data.config\.toml}'"; }
cm_scrape() { ksi "kubectl -n $NS get cm categraf-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}'"; }
w() { vmq "count(count_over_time($1[90s]))" | jq -r '.data.result[0].value[1] // "0"'; }
upv() { vmq "up{$1}" | jq -r '.data.result[0].value[1] // "absent"'; }
rev() { ksi "helm list -n $NS -o json" | jq -r '.[0].revision'; }
shots() { { echo '```'; echo "revision=$(rev)"; echo '```'; } >>"$F"; }

# ============================================================ C1 customLabels
upg "C1 (4.1) customLabels region=cn-shanghai" --set categraf.customLabels.region=cn-shanghai
{
  echo "### C1 断言"; echo '```'
  cm_node | sed -n '/\[global.labels\]/,/^\[/p'
  cm_scrape | sed -n '1,10p'
  sleep 40
  echo "metrics count({region=\"cn-shanghai\"}) = $(w '{region="cn-shanghai"}')"
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")|\"  \(.ident) region=\(.tags_maps.region // \"-\")\""
  echo '```'
} >>"$F"
assert_eq "C1-config region" "1" "$(cm_node | grep -c 'region = "cn-shanghai"')"
assert_eq "C1-scrape region" "1" "$(cm_scrape | grep -c 'region: "cn-shanghai"')"
assert_ge "C1-metrics region 标签" "1" "$(w '{region="cn-shanghai"}')"
assert_eq "C1-设备 tags region" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\" and .tags_maps.region==\"cn-shanghai\")]|length")"
restore
assert_eq "C1-恢复后无 region" "0" "$(cm_node | grep -c 'region = "cn-shanghai"')"

# ============================================================ C2 参数+hostExec+operator
upg "C2 (4.2/4.12/4.14) 参数变更 + hostExec 关 + privileged=false + operator 关" \
  --set categraf.config.interval=25 --set categraf.writer.batch=4000 \
  --set categraf.heartbeat.interval=15 --set categraf.heartbeat.timeout=7000 --set categraf.heartbeat.dialTimeout=3500 \
  --set nodeCategraf.hostExec.enabled=false --set nodeCategraf.securityContext.privileged=false \
  --set operator.enabled=false
{
  echo "### C2 断言"; echo '```'
  cm_node | grep -E '^\[global\]|^interval =|^batch =|^chan_size =|^\[heartbeat\]|^timeout =|^dial_timeout ='
  echo '--- node agent securityContext / ibex / HOST_EXEC ---'
  ksi "kubectl -n $NS get pods -l component=categraf -o jsonpath='{.items[0].spec.containers[0].securityContext}'; echo"
  echo "ibex volumes: $(ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.volumes[*].name}'" | grep -c ibex || true)"
  echo "HOST_EXEC_PROFILE=$(ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"CATEGRAF_HOST_EXEC_PROFILE\")].value}'")"
  echo '--- operator 资源 ---'
  ksi "kubectl -n $NS get deploy 2>/dev/null | grep operator || echo '(operator 已移除)'"
  echo "设备数=$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
  echo '```'
} >>"$F"
assert_eq "C2-interval=25" "1" "$(cm_node | grep -c '^interval = 25')"
assert_eq "C2-batch=4000" "1" "$(cm_node | grep -c '^batch = 4000')"
assert_eq "C2-hb interval=15" "1" "$(cm_node | grep -c '^interval = 15')"
assert_eq "C2-privileged=false" "false" "$(ksi "kubectl -n $NS get pods -l component=categraf -o jsonpath='{.items[0].spec.containers[0].securityContext.privileged}'")"
assert_eq "C2-HOST_EXEC_PROFILE=false" "false" "$(ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"CATEGRAF_HOST_EXEC_PROFILE\")].value}'")"
assert_eq "C2-无 ibex 卷" "0" "$(ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.volumes[*].name}'" | grep -c ibex || true)"
assert_eq "C2-operator 已移除" "0" "$(ksi "kubectl -n $NS get deploy -o name" | grep -c operator || true)"
assert_ge "C2-受限模式仍采集" "1" "$(w 'node_cpu_seconds_total')"
restore
sleep 20
assert_eq "C2-恢复后 operator Running" "1" "$(ksi "kubectl -n $NS get pods -l component=operator --no-headers | grep -c '1/1'")"

# ============================================================ C3 extraScrapeConfigs
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
upg_f "C3 (4.4) extraScrapeConfigs 注入 customer-custom-job" "$EXTRA"
{
  echo "### C3 断言"; echo '```'
  cm_scrape | grep -nE "job_name|customer"
  sleep 50
  echo "up{job=\"customer-custom-job\"} = $(upv 'job="customer-custom-job"')"
  echo '```'
} >>"$F"
assert_eq "C3-config 含自定义 job" "1" "$(cm_scrape | grep -c "job_name: 'customer-custom-job'")"
assert_eq "C3-新 job up=1" "1" "$(upv 'job="customer-custom-job"')"
REV0=$(rev)
{
  echo "### C3-负向：extraScrapeConfigs 非 list"; echo '```'
  echo "\$ helm upgrade --set appMetrics.extraScrapeConfigs=notalist（应失败且不改 revision）"
  ksi "helm upgrade $REL $PKG -n $NS -f $VALS --set appMetrics.extraScrapeConfigs=notalist --timeout 120s 2>&1 | tail -2"
  echo "revision: $REV0 -> $(rev)"
  echo '```'
} >>"$F"
assert_eq "C3-负向不改变 revision" "$REV0" "$(rev)"
restore
assert_eq "C3-恢复后无自定义 job" "0" "$(cm_scrape | grep -c 'customer-custom-job')"

# ============================================================ C4 annotation path
{
  echo "## C4 (4.3) annotation 自动发现：改坏 prometheus.io/path 验证 relabel 生效"; echo '```'
  echo "改前 up{job=\"app-metrics\"} = $(upv 'job="app-metrics"')"
  vmq 'up{job="app-metrics"}' | jq -r '.data.result[]? | "  up=\(.value[1]) instance=\(.metric.instance) service=\(.metric.service // "-") team=\(.metric.team // "-") namespace=\(.metric.namespace // "-")"'
  ksi "kubectl -n $NS patch deploy annotated-metrics-test --type merge -p '{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"prometheus.io/path\":\"/metrics-broken\"}}}}}' >/dev/null; kubectl -n $NS rollout status deploy/annotated-metrics-test --timeout=120s"
  echo '--- 等待 75s ---'; sleep 75
  DOWN_UP=$(upv 'job="app-metrics"'); echo "改坏后 up = $DOWN_UP"
  ksi "kubectl -n $NS patch deploy annotated-metrics-test --type merge -p '{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"prometheus.io/path\":\"/metrics\"}}}}}' >/dev/null; kubectl -n $NS rollout status deploy/annotated-metrics-test --timeout=120s"
  echo '--- 等待 60s ---'; sleep 60
  RECOVER_UP=$(upv 'job="app-metrics"'); echo "恢复后 up = $RECOVER_UP"
  echo '```'
} >>"$F"
assert_eq "C4-改坏 path 后 target down" "0" "${DOWN_UP:-x}"
assert_eq "C4-恢复 path 后 target up" "1" "${RECOVER_UP:-x}"

# ============================================================ C5 inputs 组合
upg "C5 (4.11) inputs 组合关闭：cadvisor / nodeExporter / hostNative.disk" \
  --set nodeCategraf.inputs.cadvisor=false --set nodeCategraf.inputs.nodeExporter=false --set nodeCategraf.inputs.hostNative.disk=false
{
  echo "### C5 断言"; echo '```'
  ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}' | tr ' ' '\n' | grep -E 'input|conf$' | head -20"
  sleep 100
  echo "count_over_time(up{job=\"kubelet\"}[90s])       = $(w 'up{job="kubelet"}')"
  echo "count_over_time(node_cpu_seconds_total[90s])   = $(w 'node_cpu_seconds_total')"
  echo "count_over_time(disk_used[90s])                = $(w 'disk_used')"
  echo '```'
} >>"$F"
assert_eq "C5-cadvisor 关闭后 kubelet up 消失" "0" "$(w 'up{job="kubelet"}')"
assert_eq "C5-nodeExporter 关闭后 node_cpu 消失" "0" "$(w 'node_cpu_seconds_total')"
assert_eq "C5-hostNative.disk 关闭后 disk_used 消失" "0" "$(w 'disk_used')"
restore
sleep 75
assert_ge "C5-恢复后 node_cpu" "1" "$(w 'node_cpu_seconds_total')"
assert_ge "C5-恢复后 disk_used" "1" "$(w 'disk_used')"
assert_ge "C5-恢复后 kubelet up" "1" "$(w 'up{job="kubelet"}')"

# ============================================================ C6 组件/job 组合
upg "C6 (4.5/4.6/4.7/4.9/4.10) 组件组合：KS 指标 job 关 + coreDns 关 + kubeProxy 关 + networkPlugin 关 + controlPlane 开" \
  --set ksmCategraf.jobs.kubeStateMetrics=false --set coreDns.enabled=false --set kubeProxy.enabled=false \
  --set networkPlugin.calico.enabled=false --set networkPlugin.cilium.enabled=false --set controlPlane.enabled=true
{
  echo "### C6 断言"; echo '```'
  cm_scrape | grep -nE "job_name"
  echo '--- 等待 100s ---'; sleep 100
  for j in coredns kube-proxy kube-state-metrics apiserver kube-controller-manager kube-scheduler etcd calico cilium; do
    printf '  up{%s}=%s  (90s series=%s)\n' "$j" "$(upv "job=\"$j\"")" "$(w "up{job=\"$j\"}")"
  done
  echo '--- 控制平面 job 渲染 ---'
  cm_scrape | grep -A6 -E "job_name: '(apiserver|kube-controller-manager|kube-scheduler|etcd)'" | grep -E 'job_name|replacement' | head -12
  echo '```'
} >>"$F"
assert_eq "C6-KSM job 移除" "0" "$(cm_scrape | grep -c "job_name: 'kube-state-metrics'")"
assert_eq "C6-coredns job 移除" "0" "$(cm_scrape | grep -c "job_name: 'coredns'")"
assert_eq "C6-networkPlugin job 移除" "0" "$(cm_scrape | grep -cE "job_name: '(calico|cilium)'")"
assert_eq "C6-controlPlane 4 job" "4" "$(cm_scrape | grep -cE "job_name: '(apiserver|kube-controller-manager|kube-scheduler|etcd)'")"
assert_eq "C6-kubeProxy 输入移除" "0" "$(ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'" | grep -c 'kube-proxy')"
assert_eq "C6-运行时 coredns up 消失" "0" "$(w 'up{job="coredns"}')"
assert_eq "C6-运行时 kube-proxy up 消失" "0" "$(w 'up{job="kube-proxy"}')"
assert_eq "C6-运行时 KSM up 消失" "0" "$(w 'up{job="kube-state-metrics"}')"
assert_eq "C6-apiserver 可采集" "1" "$(upv 'job="apiserver"')"
restore
sleep 75
assert_ge "C6-恢复后 coredns" "1" "$(w 'up{job="coredns"}')"
assert_ge "C6-恢复后 kube-proxy" "1" "$(w 'up{job="kube-proxy"}')"
assert_ge "C6-恢复后 KSM" "1" "$(w 'up{job="kube-state-metrics"}')"

# ============================================================ C7 KSM 部署关闭
upg "C7 (4.5) kubeStateMetrics.enabled=false" --set kubeStateMetrics.enabled=false
{
  echo "### C7 断言"; echo '```'
  ksi "kubectl -n $NS get deploy,svc 2>/dev/null | grep kube-state-metrics || echo '(KSM Deployment/Service 已移除)'"
  sleep 90
  echo "up{job=\"kube-state-metrics\"} = $(upv 'job="kube-state-metrics"')"
  echo '```'
} >>"$F"
assert_eq "C7-KSM Deployment 移除" "0" "$(ksi "kubectl -n $NS get deploy -o name" | grep -c 'kube-state-metrics' || true)"
assert_eq "C7-KSM target 掉线" "0" "$(upv 'job="kube-state-metrics"')"
restore
sleep 75
assert_eq "C7-恢复后 KSM up" "1" "$(upv 'job="kube-state-metrics"')"

# ============================================================ C8 RBAC
R="$EV/31-rbac.md"; ev "$R" "G4 RBAC can-i 断言"
{
  echo '## operator SA'; echo '```'
  for q in "get nodes" "list nodes" "get daemonsets.apps -n categraf" "create leases.coordination.k8s.io -n categraf" "create secrets -n categraf" "list pods -n categraf"; do
    printf '  %-48s %s\n' "$q" "$(ksi "kubectl auth can-i $q --as=system:serviceaccount:categraf:categraf-operator" 2>&1)"; done
  echo '```'; echo '## node-agent SA'; echo '```'
  for q in "list pods" "get nodes/metrics" "get nodes/stats" "get nodes/proxy" "list endpointslices.discovery.k8s.io" "get /metrics" "create secrets -n categraf"; do
    printf '  %-48s %s\n' "$q" "$(ksi "kubectl auth can-i $q --as=system:serviceaccount:categraf:categraf" 2>&1)"; done
  echo '```'
} >>"$R"
assert_eq "C8-operator list nodes" "yes" "$(ksi "kubectl auth can-i list nodes --as=system:serviceaccount:categraf:categraf-operator 2>/dev/null")"
assert_eq "C8-operator create leases" "yes" "$(ksi "kubectl auth can-i create leases.coordination.k8s.io -n categraf --as=system:serviceaccount:categraf:categraf-operator 2>/dev/null")"
assert_eq "C8-operator 不可建 secret" "no" "$(ksi "kubectl auth can-i create secrets -n categraf --as=system:serviceaccount:categraf:categraf-operator 2>/dev/null")"
assert_eq "C8-node-agent list pods" "yes" "$(ksi "kubectl auth can-i list pods --as=system:serviceaccount:categraf:categraf 2>/dev/null")"
assert_eq "C8-node-agent get nodes/metrics" "yes" "$(ksi "kubectl auth can-i get nodes/metrics --as=system:serviceaccount:categraf:categraf 2>/dev/null")"
assert_eq "C8-node-agent 不可建 secret" "no" "$(ksi "kubectl auth can-i create secrets -n categraf --as=system:serviceaccount:categraf:categraf 2>/dev/null")"

# ============================================================ C9 多 Release 隔离
TOKEN=$(security find-generic-password -s flashcat-test-token -a test -w)
cat >/tmp/categraf-rg-values.yaml <<YAML
categraf:
  clusterName: k8s-flashcat-test-20261029-rg
  customLabels:
    environment: test
    owner: platform
nodeCategraf:
  hostname: "\${cluster}-\$hostname"
operator:
  enabled: true
  userToken: "$TOKEN"
YAML
push /tmp/categraf-rg-values.yaml "$RG"; rm -f /tmp/categraf-rg-values.yaml
{
  echo "## C9 (4.13) 多 Release 隔离（ns=categraf-rg, clusterName=…-rg, hostname 模板）"; echo '```'
  ksi "helm upgrade --install categraf-rg $PKG -n categraf-rg --create-namespace -f $VALS -f $RG --timeout 240s 2>&1 | tail -4"
  echo '--- 资源命名 ---'; ksi "kubectl -n categraf-rg get ds,sts,deploy,cm -o name | head -14"
  echo '--- ClusterRole 隔离 ---'; ksi "kubectl get clusterrole 2>/dev/null | grep -E 'categraf-rg|categraf-categraf' | head -8"
  echo '--- 等待 50s 设备 ---'; sleep 50
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r '.dat.list[]|select(.tags_maps.cluster|test("rg$"))|"  \(.ident) cluster=\(.tags_maps.cluster) target_up=\(.target_up)"'
  echo '--- 主集群设备 ---'
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")|\"  \(.ident) target_up=\(.target_up)\""
  echo '```'
} >>"$F"
assert_eq "C9-rg 设备数" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster|test(\"rg$\"))]|length")"
assert_eq "C9-ident 含 -rg-" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster|test(\"rg$\"))|select(.ident|contains(\"-rg-\"))]|length")"
assert_eq "C9-主集群设备不受影响" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
{
  echo "### C9 卸载：cleanup hook 只删本集群设备"; echo '```'
  ksi "helm uninstall categraf-rg -n categraf-rg --timeout 600s 2>&1 | tail -2"
  sleep 25
  echo "rg 设备数=$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster|test(\"rg$\"))]|length")  主集群=$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
  echo '```'
} >>"$F"
sleep 20
assert_eq "C9-rg 卸载后本集群清理" "0" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster|test(\"rg$\"))]|length")"
assert_eq "C9-rg 卸载不影响主集群" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
ksi "kubectl delete namespace categraf-rg --timeout=120s >/dev/null 2>&1"

# ============================================================ 收尾
restore
ksi "kubectl -n $NS rollout status ds categraf --timeout=180s >/dev/null 2>&1; kubectl -n $NS rollout status sts categraf-ksm --timeout=180s >/dev/null 2>&1" 
sleep 45
{
  echo "## 收尾：最终状态"; echo '```'
  ksi "helm list -n $NS; echo; kubectl -n $NS get pods -o wide | head -8"
  echo "设备 target_up=2: $(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\" and .target_up==2)]|length")/3"
  echo "up 异常条数: $(vmq "up{cluster=\"$CLUSTER\"}" | jq '[.data.result[]|select(.value[1]!="1")]|length')"
  echo "series: $(vmq "count({cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1]')"
  echo '```'
} >>"$F"

echo "G4(lean) 完成: $F"
echo "PASS=$(grep -c PASS "$EV/results.tsv") FAIL=$(grep -c FAIL "$EV/results.tsv" || true)"
grep FAIL "$EV/results.tsv" | tail -8 || echo "无 FAIL"
