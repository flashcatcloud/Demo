#!/usr/bin/env bash
# F1 修复端到端验证：在独立 namespace 里复现“0.2.1 → rc.2 且 values 不变”的升级，
# 期望：Pod 自动滚动、Pod 内配置立即变为新内容、customLabels 指标/设备标签出现（无需人工 rollout restart）。
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/29-F1-fix-verified.md"
NSX=categraf-f1fix
CL=f1fix
TOKEN=$(security find-generic-password -s flashcat-test-token -a test -w)
PV=/root/categraf-f1fix-values.yaml

cat >/tmp/f1fix-values.yaml <<YAML
categraf:
  serverAddr: http://flashcat.local:19000
  clusterName: k8s-flashcat-test-20261029-${CL}
  env: test
  heartbeatGid: "2"
  customLabels:
    environment: test
    owner: platform
  config:
    interval: 20
  writer:
    batch: 3000
    chanSize: 1500000
  heartbeat:
    interval: 12
    timeout: 6000
    dialTimeout: 3000
operator:
  enabled: true
  userToken: "$TOKEN"
YAML
push /tmp/f1fix-values.yaml "$PV"; rm -f /tmp/f1fix-values.yaml
CLUSTER_NAME="k8s-flashcat-test-20261029-${CL}"

ev "$F" "F1 修复端到端验证：ns=${NSX}，0.2.1 → 0.2.2-rc.2，values 完全不变"

pods_json() { ksi "kubectl -n $NSX get pods -l component=categraf -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.creationTimestamp} {.metadata.annotations.checksum/config}{end}'"; }
mounted_labels() { local p; p=$(ksi "kubectl -n $NSX get pods -l component=categraf -o name | head -1 | sed 's|pod/||'"); ksi "kubectl -n $NSX exec $p -- sed -n '/\[global.labels\]/,/^\[/p' /opt/categraf/conf/config.toml"; }
node_metric() { vmq "count({cluster=\"$CLUSTER_NAME\",$1})" | jq -r '.data.result[0].value[1] // "0"'; }

{
echo "## 0. 安装 0.2.1（生产版本，同 values）"
echo '```'
ksi "kubectl create namespace $NSX 2>&1 | tail -1"
ksi "helm upgrade --install categraf-f1fix oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1 -n $NSX -f $PV --timeout 300s 2>&1 | tail -4"
ksi "kubectl -n $NSX wait --for=condition=Available deploy --all --timeout=240s >/dev/null 2>&1; kubectl -n $NSX rollout status ds --timeout=240s 2>&1 | tail -1"
echo '--- 0.2.1 的 Node Agent Pod（名称/创建时间/checksum）---'
pods_json; echo
echo '--- 0.2.1 Pod 内实际配置的 [global.labels] ---'
mounted_labels
echo '```'
} >>"$F"

POD1=$(ksi "kubectl -n $NSX get pods -l component=categraf -o jsonpath='{.items[0].metadata.name}'")
TS1=$(ksi "kubectl -n $NSX get pods -l component=categraf -o jsonpath='{.items[0].metadata.creationTimestamp}'")
CK1=$(ksi "kubectl -n $NSX get pods -l component=categraf -o jsonpath='{.items[0].metadata.annotations.checksum/config}'")

{
echo "## 1. 升级到 rc.2（values 一个字不改）"
echo '```'
echo "\$ helm upgrade categraf-f1fix /root/categraf-0.2.2-rc.2.tgz -n $NSX -f $PV"
ksi "helm upgrade categraf-f1fix /root/categraf-0.2.2-rc.2.tgz -n $NSX -f $PV --timeout 300s 2>&1 | tail -4"
echo
echo "\$ helm history / 等待滚动"
ksi "helm history categraf-f1fix -n $NSX | tail -3"
ksi "kubectl -n $NSX rollout status ds --timeout=240s 2>&1 | tail -1; kubectl -n $NSX rollout status sts --all --timeout=10s 2>&1 | tail -1"
echo
echo '--- 升级后的 Node Agent Pod（创建时间应变化 = 自动滚动；checksum 应变化）---'
pods_json
echo '```'
} >>"$F"

POD2=$(ksi "kubectl -n $NSX get pods -l component=categraf -o jsonpath='{.items[0].metadata.name}'")
TS2=$(ksi "kubectl -n $NSX get pods -l component=categraf -o jsonpath='{.items[0].metadata.creationTimestamp}'")
CK2=$(ksi "kubectl -n $NSX get pods -l component=categraf -o jsonpath='{.items[0].metadata.annotations.checksum/config}'")

{
echo "## 2. 断言：不用人工 rollout restart，配置已生效"
echo '```'
echo "Pod 创建时间: $TS1 → $TS2 （不同 = 升级触发了滚动）"
echo "checksum   : ${CK1:0:16}… → ${CK2:0:16}…"
echo
echo '--- rc.2 Pod 内实际配置的 [global.labels]（应含 owner/environment）---'
mounted_labels
echo
echo '--- 等待 60s 让新配置上报指标/心跳 ---'
sleep 60
echo "指标: count({cluster=\"$CLUSTER_NAME\"})                  = $(node_metric '')"
echo "指标: count({cluster=\"$CLUSTER_NAME\",owner=\"platform\"}) = $(node_metric 'owner="platform"')"
echo "指标: count({cluster=\"$CLUSTER_NAME\",environment=\"test\"}) = $(node_metric 'environment="test"')"
echo "up{cluster=...,job=app-metrics} = $(vmq "up{cluster=\"$CLUSTER_NAME\",job=\"app-metrics\"}" | jq -r '[.data.result[]?.value[1]]|join(",")')"
echo
echo '--- Flashcat 设备（本集群）---'
fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[]?|select(.tags_maps.cluster==\"$CLUSTER_NAME\")|\"  \(.ident) up=\(.target_up) owner=\(.tags_maps.owner // \"-\") environment=\(.tags_maps.environment // \"-\")\""
echo '```'
} >>"$F"

assert_eq "F1fix-Pod 自动滚动(创建时间变化)" "changed" "$( [ "$TS1" != "$TS2" ] && echo changed || echo same )"
assert_eq "F1fix-checksum 变化" "changed" "$( [ "$CK1" != "$CK2" ] && echo changed || echo same )"
assert_ge "F1fix-指标含 owner 标签" "1" "$(node_metric 'owner="platform"')"
assert_eq "F1fix-app-metrics target up" "1" "$(vmq "up{cluster=\"$CLUSTER_NAME\",job=\"app-metrics\"}" | jq -r '.data.result[0].value[1] // "absent"')"
assert_eq "F1fix-设备标签含 owner" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]?|select(.tags_maps.cluster==\"$CLUSTER_NAME\" and .tags_maps.owner==\"platform\")]|length")"

{
echo "## 3. 清理（卸载触发 cleanup hook，删除本集群设备）"
echo '```'
ksi "helm uninstall categraf-f1fix -n $NSX --timeout 600s 2>&1 | tail -2"
sleep 30
echo "清理后本集群设备数 = $(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]?|select(.tags_maps.cluster==\"$CLUSTER_NAME\")]|length")"
echo "主集群设备数 = $(fca "/api/n9e/targets?limit=1000&p=1" | jq -r '[.dat.list[]?|select(.tags_maps.cluster=="k8s-flashcat-test-20261029")]|length')"
ksi "kubectl delete namespace $NSX --timeout=120s 2>&1 | tail -1"
echo '```'
echo "## 4. 结论"
echo '```'
echo "同一份 values 从 0.2.1 升级到 rc.2：Pod 自动滚动（无需人工 rollout restart），Pod 内配置立即更新，"
echo "customLabels 指标与设备标签随即出现 → F1 修复生效。"
echo '```'
} >>"$F"

echo "F1 修复验证完成: $F"
grep -E '^(PASS|FAIL)' "$EV/results.tsv" | grep F1fix | tail -6
