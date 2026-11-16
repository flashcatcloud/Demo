#!/usr/bin/env bash
# G4 修正轮 2：C4 path 覆盖（子查询方法）、C6-controlPlane apiserver 诊断、C9 多 Release 重测
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/33-features-fix2.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.1.tgz
RG=/root/categraf-rg-values.yaml
ev "$F" "G4 修正轮2：C4 用子查询消除 stale series；C6 apiserver 直连诊断；C9 多 Release 重测（含 push 校验）"
cm_scrape() { ksi "kubectl -n $NS get cm categraf-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}'"; }
upfresh1() { vmq "count(count_over_time((up{$1} == 1)[60s:15s]))" | jq -r '.data.result[0].value[1] // "0"'; }
upv() { vmq "up{$1}" | jq -r '[.data.result[]?.value[1]] | join(",")'; }
restore() { ksi "helm upgrade $REL $PKG -n $NS -f $VALS --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1; }

echo '--- C4 path 覆盖（子查询方法）---'
{
  echo "## C4-2 用子查询 (up==1)[60s:15s] 排除 stale series"; echo '```'
  echo "基线: 60s 内 up=1 的 app-metrics series 数 = $(upfresh1 'job="app-metrics"')"
  ksi "kubectl -n $NS patch deploy annotated-metrics-test --type merge -p '{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"prometheus.io/path\":\"/metrics-broken\"}}}}}' >/dev/null 2>&1; kubectl -n $NS rollout status deploy/annotated-metrics-test --timeout=120s >/dev/null 2>&1"
  sleep 100
  DOWN_FRESH=$(upfresh1 'job="app-metrics"'); echo "改坏后: up 全集=[$(upv 'job="app-metrics"')]  60s 内 up=1 数=$DOWN_FRESH"
  echo "当前 Pod 注解:"; ksi "kubectl -n $NS get pods -l app.kubernetes.io/name=annotated-metrics-test -o jsonpath='{.items[0].metadata.annotations}'"
  ksi "kubectl -n $NS patch deploy annotated-metrics-test --type merge -p '{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"prometheus.io/path\":\"/metrics\"}}}}}' >/dev/null 2>&1; kubectl -n $NS rollout status deploy/annotated-metrics-test --timeout=120s >/dev/null 2>&1"
  sleep 80
  RECOVER_FRESH=$(upfresh1 'job="app-metrics"'); echo "恢复后: 60s 内 up=1 数=$RECOVER_FRESH"
  echo '```'
} >>"$F"
assert_eq "C4-2改坏后无新鲜 up=1" "0" "${DOWN_FRESH:-x}"
assert_ge "C4-2恢复后新鲜 up=1" "1" "${RECOVER_FRESH:-0}"
{
  echo "### C4-2 结论记录"; echo '```'
  echo "说明：上方三条为现场打印；最终断言使用改坏后/恢复后的独立查询（见 results.tsv C4-2 前缀）"
  echo '```'
} >>"$F"

echo '--- C6 controlPlane apiserver 诊断 ---'
ksi "helm upgrade $REL $PKG -n $NS -f $VALS --set controlPlane.enabled=true --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
{
  echo "## C6-2 controlPlane apiserver"; echo '```'
  cm_scrape | sed -n "/job_name: 'apiserver'/,/job_name: 'kube-controller-manager'/p"
  sleep 90
  echo "up{job=apiserver} = [$(upv 'job="apiserver"')]"
  echo '--- KSM Agent 日志中 apiserver/scrape 错误 ---'
  ksi "kubectl -n $NS logs -l component=categraf-ksm --tail=200 2>/dev/null | grep -iE 'apiserver|scrape|error' | tail -10"
  echo '--- 从 KSM Pod 直连 apiserver /metrics 诊断 ---'
  K=$(ksi "kubectl -n $NS get pods -l component=categraf-ksm -o name | head -1 | sed 's|pod/||'")
  ksi "kubectl -n $NS exec $K -- sh -c 'TOKEN=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); (command -v curl || command -v wget); curl -sk -o /dev/null -w \"curl_http=%{http_code}\n\" -H \"Authorization: Bearer \$TOKEN\" https://kubernetes.default.svc/metrics 2>&1 || wget -q --no-check-certificate --header=\"Authorization: Bearer \$TOKEN\" -O /dev/null https://kubernetes.default.svc/metrics 2>&1'"
  echo '```'
} >>"$F"
restore

echo '--- C9 多 Release 重测（push 校验 + 120s 等待）---'
TOKEN=$(security find-generic-password -s flashcat-test-token -a test -w)
cat >/tmp/rg.yaml <<YAML
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
push /tmp/rg.yaml "$RG"; rm -f /tmp/rg.yaml
{
  echo "## C9-2 多 Release 重测"; echo '```'
  echo '$ ls -l 远端 values 文件'; ksi "ls -l $RG"
  echo '$ helm upgrade --install categraf-rg'
  ksi "helm upgrade --install categraf-rg $PKG -n categraf-rg --create-namespace -f $VALS -f $RG --timeout 240s 2>&1 | tail -4"
  echo '$ 资源命名'; ksi "kubectl -n categraf-rg get ds,sts,deploy -o name 2>&1 | head -8"
  echo '$ ClusterRole'; ksi "kubectl get clusterrole 2>/dev/null | grep 'categraf-rg-' | head -6"
  echo '$ 等待 120s 设备'; sleep 120
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r '.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))|"  \(.ident) cluster=\(.tags_maps.cluster) up=\(.target_up)"'
  echo '$ rg 内 Agent 日志（若没注册，查日志）'
  ksi "kubectl -n categraf-rg logs -l component=categraf --tail=40 2>/dev/null | tail -14"
  echo '```'
} >>"$F"
rgc() { fca "/api/n9e/targets?limit=1000&p=1" | jq '[.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))]|length'; }
mainc() { fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]?|select(.tags_maps.cluster?==\"$CLUSTER\")]|length"; }
{
  echo '### C9-2 卸载'; echo '```'
  ksi "helm uninstall categraf-rg -n categraf-rg --timeout 600s 2>&1 | tail -2"
  sleep 40
  echo "rg 设备=$(rgc) 主集群=$(mainc)"
  echo '```'
} >>"$F"
assert_eq "C9-2-rg 设备数" "3" "$(rgc)"
assert_eq "C9-2-rg 卸载后清理" "0" "$(rgc)"
assert_eq "C9-2-主集群不受影响" "3" "$(mainc)"
ksi "kubectl delete namespace categraf-rg --timeout=120s >/dev/null 2>&1"
echo "G4 修正轮2 完成: $F"
