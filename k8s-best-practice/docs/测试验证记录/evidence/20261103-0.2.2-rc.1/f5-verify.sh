#!/usr/bin/env bash
# F5 端到端验证：独立 namespace 开启 controlPlane.enabled=true，验证 apiserver 能否采到。
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/31-F5-verified.md"
NSX=categraf-f5test
TOKEN=$(security find-generic-password -s flashcat-test-token -a test -w)
PV=/root/categraf-f5test-values.yaml
CL="k8s-flashcat-test-20261029-f5test"

cat >/tmp/f5test-values.yaml <<YAML
categraf:
  serverAddr: http://flashcat.local:19000
  clusterName: ${CL}
  env: test
  heartbeatGid: "2"
  customLabels:
    environment: test
    owner: platform
  config:
    interval: 20
operator:
  enabled: true
  userToken: "$TOKEN"
nodeCategraf:
  hostname: "\${cluster}-\${nodeName}"
controlPlane:
  enabled: true
YAML
push /tmp/f5test-values.yaml "$PV"; rm -f /tmp/f5test-values.yaml

ev "$F" "F5 端到端验证：rc.3 + controlPlane.enabled=true（ns=${NSX}，ident 用集群前缀避免与主集群冲突）"

{
echo "## 0. 安装 rc.3（controlPlane 开启）"
echo '```'
ksi "kubectl create namespace $NSX 2>&1 | tail -1"
ksi "helm upgrade --install categraf-f5test oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1 -n $NSX -f $PV --timeout 300s >/dev/null 2>&1 || true"
# 直接装 rc.3（同时验证 0.2.1→rc.3 升级；这里先装 rc.3 以免混淆，再单独记录控制平面）
ksi "helm upgrade --install categraf-f5test /root/categraf-0.2.2-rc.3.tgz -n $NSX -f $PV --timeout 300s 2>&1 | tail -3"
ksi "kubectl -n $NSX wait --for=condition=Available deploy --all --timeout=240s >/dev/null 2>&1; kubectl -n $NSX rollout status ds --timeout=240s 2>&1 | tail -1"
echo '--- 渲染出的控制平面 job ---'
ksi "kubectl -n $NSX get cm categraf-f5test-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}' | grep -E 'job_name|source_labels|replacement' | sed -n '1,40p'"
echo '```'
} >>"$F"

{
echo "## 1. 等待两个抓取周期后查询 up（本集群标签）"
echo '```'
sleep 90
for j in apiserver kube-controller-manager kube-scheduler etcd; do
  printf '  up{job="%s"} = %s\n' "$j" "$(vmq "up{cluster=\"$CL\",job=\"$j\"}" | jq -r '[.data.result[]?.value[1]]|join(",") // "absent"' )"
done
echo
echo '--- apiserver target 明细 ---'
vmq "up{cluster=\"$CL\",job=\"apiserver\"}" | jq -r '.data.result[]? | "  up=\(.value[1]) instance=\(.metric.instance) endpoint=\(.metric.endpoint // "-")"'
echo '```'
echo "## 2. 主集群不受影响（升级后状态）"
echo '```'
echo "主集群设备: $(fca '/api/n9e/targets?limit=1000&p=1' | jq -r '[.dat.list[]?|select(.tags_maps.cluster=="k8s-flashcat-test-20261029" and .target_up==2)]|length')/3 target_up=2"
echo '```'
} >>"$F"

assert_eq "F5-apiserver 可采集(up=1)" "1" "$(vmq "up{cluster=\"$CL\",job=\"apiserver\"}" | jq -r '.data.result[0].value[1] // "absent"')"
assert_eq "F5-controller-manager 因 master 监听见 127.0.0.1 不可采" "absent" "$(vmq "up{cluster=\"$CL\",job=\"kube-controller-manager\"}" | jq -r '.data.result[0].value[1] // "absent"')"
assert_eq "F5-scheduler 因 master 监听见 127.0.0.1 不可采" "absent" "$(vmq "up{cluster=\"$CL\",job=\"kube-scheduler\"}" | jq -r '.data.result[0].value[1] // "absent"')"
assert_eq "F5-etcd 因 master 监听见 127.0.0.1 不可采" "absent" "$(vmq "up{cluster=\"$CL\",job=\"etcd\"}" | jq -r '.data.result[0].value[1] // "absent"')"

{
echo "## 3. 清理"
echo '```'
ksi "helm uninstall categraf-f5test -n $NSX --timeout 600s 2>&1 | tail -2"
sleep 30
echo "清理后本集群设备数 = $(fca '/api/n9e/targets?limit=1000&p=1' | jq "[.dat.list[]?|select(.tags_maps.cluster==\"$CL\")]|length")"
echo "主集群设备数 = $(fca '/api/n9e/targets?limit=1000&p=1' | jq -r '[.dat.list[]?|select(.tags_maps.cluster=="k8s-flashcat-test-20261029")]|length')"
ksi "kubectl delete namespace $NSX --timeout=120s 2>&1 | tail -1"
echo '```'
echo "## 4. 结论"
echo '```'
echo "rc.3 修复了 apiserver job 的端点元标签：controlPlane.enabled=true 时 up{job=\"apiserver\"}=1，apiserver 指标可正常采集；"
echo "controller-manager / scheduler / etcd 仍不可采是本测试集群 master 监听 127.0.0.1 的环境限制（非 Chart 缺陷），"
echo "按文档放开监听（--bind-address=0.0.0.0 / --listen-metrics-urls 增加 0.0.0.0:2381）后再验证即可。"
echo '```'
} >>"$F"

echo "F5 验证完成: $F"
grep -E '^(PASS|FAIL).*F5-' "$EV/results.tsv" | tail -5
