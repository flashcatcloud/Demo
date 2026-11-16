#!/usr/bin/env bash
# G4 修正轮：用“短窗口 count_over_time”判定指标消失/存在，修正首轮的窗口误判；并重测 C3/C4/C9
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/32-features-fix.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.1.tgz
EXTRA=/root/categraf-extra-scrape-values.yaml
RG=/root/categraf-rg-values.yaml

ev "$F" "G4 修正轮：指标消失/存在改用短窗口（60s/45s）+ 足够长的观察时间；修正 C3 grep 与 C9 设备等待"

cm_node()   { ksi "kubectl -n $NS get cm categraf-config -o jsonpath='{.data.config\.toml}'"; }
cm_scrape() { ksi "kubectl -n $NS get cm categraf-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}'"; }
wshort() { vmq "count(count_over_time($1[${2:-60s}]))" | jq -r '.data.result[0].value[1] // "0"'; }
upv() { vmq "up{$1}" | jq -r '[.data.result[]?.value[1]] | join(",")' ; }
up1() { vmq "count(up{$1} == 1)" | jq -r '.data.result[0].value[1] // "0"'; }
restore() { ksi "helm upgrade $REL $PKG -n $NS -f $VALS --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1; }

# ---------- C3：配置断言修正（toYaml 无引号） ----------
ksi "helm upgrade $REL $PKG -n $NS -f $VALS -f $EXTRA --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
{
  echo "## C3-fix extraScrapeConfigs"; echo '```'
  cm_scrape | grep -nE 'job_name|customer|namespaces' | head -12
  sleep 40
  echo "up{job=customer-custom-job} = $(upv 'job="customer-custom-job"')"
  echo '```'
} >>"$F"
assert_eq "C3f-config 含自定义 job" "1" "$(cm_scrape | grep -c 'job_name: customer-custom-job')"
assert_eq "C3f-新 job up=1" "1" "$(up1 'job="customer-custom-job"')"
restore
assert_eq "C3f-恢复后无自定义 job" "0" "$(cm_scrape | grep -c 'customer-custom-job')"

# ---------- C4：改坏 path，按“所有 target 都不再 up”判定 ----------
{
  echo "## C4-fix annotation path 生效性"; echo '```'
  echo "改前 up{job=app-metrics} 值集合 = [$(upv 'job="app-metrics"')]  up=1 数量=$(up1 'job="app-metrics"')"
  ksi "kubectl -n $NS patch deploy annotated-metrics-test --type merge -p '{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"prometheus.io/path\":\"/metrics-broken\"}}}}}' >/dev/null 2>&1; kubectl -n $NS rollout status deploy/annotated-metrics-test --timeout=120s >/dev/null 2>&1"
  sleep 110
  echo "改坏后 up 值集合 = [$(upv 'job="app-metrics"')]  up=1 数量=$(up1 'job="app-metrics"')"
  ksi "kubectl -n $NS patch deploy annotated-metrics-test --type merge -p '{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"prometheus.io/path\":\"/metrics\"}}}}}' >/dev/null 2>&1; kubectl -n $NS rollout status deploy/annotated-metrics-test --timeout=120s >/dev/null 2>&1"
  sleep 90
  echo "恢复后 up 值集合 = [$(upv 'job="app-metrics"')]  up=1 数量=$(up1 'job="app-metrics"')"
  echo '```'
} >>"$F"
assert_eq "C4f-改坏 path 后无 up=1 target" "0" "$(up1 'job="app-metrics"')"
assert_eq "C4f-恢复 path 后 up=1 target 出现" "1" "$(up1 'job="app-metrics"')"

# ---------- C5：inputs 关闭，短窗口判定消失 ----------
ksi "helm upgrade $REL $PKG -n $NS -f $VALS --set nodeCategraf.inputs.cadvisor=false --set nodeCategraf.inputs.nodeExporter=false --set nodeCategraf.inputs.hostNative.disk=false --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
{
  echo "## C5-fix inputs 关闭（观察 130s 后用 60s 短窗口判定）"; echo '```'
  sleep 130
  echo "60s 内 up{job=kubelet} series      = $(wshort 'up{job="kubelet"}')"
  echo "60s 内 node_cpu_seconds_total      = $(wshort 'node_cpu_seconds_total')"
  echo "60s 内 disk_used                   = $(wshort 'disk_used')"
  echo '```'
} >>"$F"
assert_eq "C5f-cadvisor 关闭后 kubelet up 消失" "0" "$(wshort 'up{job="kubelet"}')"
assert_eq "C5f-nodeExporter 关闭后 node_cpu 消失" "0" "$(wshort 'node_cpu_seconds_total')"
assert_eq "C5f-hostNative.disk 关闭后 disk_used 消失" "0" "$(wshort 'disk_used')"
restore
sleep 90
assert_ge "C5f-恢复后 node_cpu" "1" "$(wshort 'node_cpu_seconds_total')"
assert_ge "C5f-恢复后 disk_used" "1" "$(wshort 'disk_used')"

# ---------- C6：组件组合，短窗口判定 ----------
ksi "helm upgrade $REL $PKG -n $NS -f $VALS --set ksmCategraf.jobs.kubeStateMetrics=false --set coreDns.enabled=false --set kubeProxy.enabled=false --set networkPlugin.calico.enabled=false --set networkPlugin.cilium.enabled=false --set controlPlane.enabled=true --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
{
  echo "## C6-fix 组件组合（观察 130s 后用 60s 短窗口判定）"; echo '```'
  sleep 130
  echo "60s 内 up{job=coredns}            = $(wshort 'up{job="coredns"}')"
  echo "60s 内 up{job=kube-proxy}         = $(wshort 'up{job="kube-proxy"}')"
  echo "60s 内 up{job=kube-state-metrics} = $(wshort 'up{job="kube-state-metrics"}')"
  echo "up{job=apiserver}                 = [$(upv 'job="apiserver"')]"
  echo "up{job=kube-controller-manager}   = [$(upv 'job="kube-controller-manager"')]"
  echo "up{job=kube-scheduler}            = [$(upv 'job="kube-scheduler"')]"
  echo "up{job=etcd}                      = [$(upv 'job="etcd"')]"
  echo '```'
} >>"$F"
assert_eq "C6f-coredns up 消失" "0" "$(wshort 'up{job="coredns"}')"
assert_eq "C6f-kube-proxy up 消失" "0" "$(wshort 'up{job="kube-proxy"}')"
assert_eq "C6f-KSM up 消失" "0" "$(wshort 'up{job="kube-state-metrics"}')"
assert_eq "C6f-apiserver up=1" "1" "$(up1 'job="apiserver"')"
restore
sleep 90
assert_ge "C6f-恢复后 coredns" "1" "$(wshort 'up{job="coredns"}')"
assert_ge "C6f-恢复后 kube-proxy" "1" "$(wshort 'up{job="kube-proxy"}')"
assert_ge "C6f-恢复后 KSM" "1" "$(wshort 'up{job="kube-state-metrics"}')"

# ---------- C7：KSM 部署关闭，短窗口判定 ----------
ksi "helm upgrade $REL $PKG -n $NS -f $VALS --set kubeStateMetrics.enabled=false --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
{
  echo "## C7-fix kubeStateMetrics.enabled=false"; echo '```'
  ksi "kubectl -n $NS get deploy 2>/dev/null | grep kube-state-metrics || echo '(KSM Deployment 已移除)'"
  sleep 130
  echo "60s 内 up{job=kube-state-metrics} = $(wshort 'up{job="kube-state-metrics"}')"
  echo "60s 内 kube_pod_info              = $(wshort 'kube_pod_info')"
  echo '```'
} >>"$F"
assert_eq "C7f-KSM Deployment 移除" "0" "$(ksi "kubectl -n $NS get deploy -o name" | grep -c 'kube-state-metrics' || true)"
assert_eq "C7f-KSM target 消失" "0" "$(wshort 'up{job="kube-state-metrics"}')"
assert_eq "C7f-kube_pod_info 停止上报" "0" "$(wshort 'kube_pod_info')"
restore
sleep 100
assert_ge "C7f-恢复后 KSM up" "1" "$(wshort 'up{job="kube-state-metrics"}')"
assert_ge "C7f-恢复后 kube_pod_info" "1" "$(wshort 'kube_pod_info')"

# ---------- C9：多 Release 隔离（等待 90s，jq 健壮化） ----------
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
rgcount() { fca "/api/n9e/targets?limit=1000&p=1" | jq '[.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))]|length'; }
maincount() { fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]?|select(.tags_maps.cluster?==\"$CLUSTER\")]|length"; }
{
  echo "## C9 多 Release 隔离（重测）"; echo '```'
  ksi "helm upgrade --install categraf-rg $PKG -n categraf-rg --create-namespace -f $VALS -f $RG --timeout 240s 2>&1 | tail -3"
  echo '--- 资源命名隔离 ---'; ksi "kubectl -n categraf-rg get ds,sts,deploy -o name | head -8"
  echo '--- ClusterRole 隔离 ---'; ksi "kubectl get clusterrole 2>/dev/null | grep -E 'categraf-rg-' | head -6"
  echo '--- 等待 90s 设备注册 ---'; sleep 90
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r '.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))|"  \(.ident) cluster=\(.tags_maps.cluster) up=\(.target_up)"'
  echo '--- 主集群设备 ---'
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[]?|select(.tags_maps.cluster?==\"$CLUSTER\")|\"  \(.ident) up=\(.target_up)\""
  echo '```'
} >>"$F"
assert_eq "C9-rg 设备数" "3" "$(rgcount)"
assert_eq "C9-ident 含 -rg-" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq '[.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))|select(.ident|contains("-rg-"))]|length')"
assert_eq "C9-主集群设备不受影响" "3" "$(maincount)"
{
  echo "### C9 卸载"; echo '```'
  ksi "helm uninstall categraf-rg -n categraf-rg --timeout 600s 2>&1 | tail -2"
  sleep 40
  echo "rg 设备数=$(rgcount)  主集群=$(maincount)"
  echo '```'
} >>"$F"
assert_eq "C9-rg 卸载后清理" "0" "$(rgcount)"
assert_eq "C9-rg 卸载不影响主集群" "3" "$(maincount)"
ksi "kubectl delete namespace categraf-rg --timeout=120s >/dev/null 2>&1"

echo "G4 修正轮完成: $F"
echo "PASS=$(grep -c PASS "$EV/results.tsv") FAIL=$(grep -c FAIL "$EV/results.tsv" || true)"
tail -20 "$EV/results.tsv"
