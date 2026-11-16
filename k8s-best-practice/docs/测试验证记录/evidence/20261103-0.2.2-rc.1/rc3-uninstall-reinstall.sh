#!/usr/bin/env bash
# 主 Release 在 rc.3 上的卸载 + 重装演练（用户已授权；预计采集中断 1-2 分钟）
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/59-rc3-uninstall-reinstall.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.3.tgz

ev "$F" "rc.3 主 Release 卸载 + 清理 Hook + 重装演练（ns=categraf）"
q_dev_all() { fca "/api/n9e/targets?limit=1000&p=1" | jq -r '[.dat.list[]?|select(.tags_maps.cluster=="'"$CLUSTER"'")]|length'; }
q_dev_up()  { fca "/api/n9e/targets?limit=1000&p=1" | jq -r '[.dat.list[]?|select(.tags_maps.cluster=="'"$CLUSTER"'" and .target_up==2)]|length'; }
q_other()   { fca "/api/n9e/targets?limit=1000&p=1" | jq -r '[.dat.list[]?|select(.tags_maps.cluster!="'"$CLUSTER"'")]|length'; }
q_series()  { vmq "count({cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1] // 0'; }
q_upbad()   { vmq "up{cluster=\"$CLUSTER\"}" | jq -r '[.data.result[]|select(.value[1]!="1")]|length'; }

{
echo "## 0. 卸载前基线（rc.3 rev37）"
echo '```'
ksi "helm list -n $NS | tail -1; kubectl -n $NS get pods --no-headers | awk '{print \$3}' | sort | uniq -c"
echo "设备: $(q_dev_all) 台，target_up=2: $(q_dev_up) 台；其它集群设备: $(q_other) 台"
echo "指标 series: $(q_series)；up 异常条数: $(q_upbad)"
echo '```'
echo "## 1. helm uninstall（观察 cleanup Hook）"
echo '```'
ksi 'rm -f /root/cleanup-hook.log /root/cleanup-hook.done; nohup bash -c "for i in \$(seq 1 120); do p=\$(kubectl -n categraf get pods -l component=operator-cleanup -o name 2>/dev/null | head -1); if [ -n \"\$p\" ]; then kubectl -n categraf logs \$p --all-containers > /root/cleanup-hook.log 2>&1; echo done > /root/cleanup-hook.done; fi; sleep 1; done" >/dev/null 2>&1 &'
echo "\$ helm uninstall categraf -n categraf"
ksi "time helm uninstall $REL -n $NS --timeout 600s 2>&1 | tail -3"
echo
echo '--- cleanup Hook 日志（设备删除）---'
ksi "cat /root/cleanup-hook.log 2>/dev/null | grep -E 'deleted target|target cleanup completed|heartbeats stopped|cleanup-once completed' | tail -10"
echo '```'
echo "## 2. 卸载后状态"
echo '```'
ksi "helm list -n $NS -q | wc -l | xargs echo 'release 数量:'; kubectl -n $NS get pods,ds,sts,deploy 2>&1 | head -8"
echo "设备: $(q_dev_all) 台；其它集群设备: $(q_other) 台"
echo '```'
} >>"$F"

assert_eq "rc3-卸载后 release 清空" "0" "$(ksi "helm list -n $NS -q | wc -l" | tr -d ' ')"
assert_eq "rc3-卸载后本集群设备清零" "0" "$(q_dev_all)"
assert_eq "rc3-卸载不影响其它集群设备" "3" "$(q_other)"

{
echo "## 3. 用 rc.3 重新安装（同一份 values）"
echo '```'
ksi "helm upgrade --install $REL $PKG -n $NS --create-namespace -f $VALS --timeout 300s 2>&1 | tail -4"
ksi "kubectl -n $NS wait --for=condition=Available deploy --all --timeout=240s >/dev/null 2>&1; kubectl -n $NS rollout status ds --timeout=240s 2>&1 | tail -1"
echo '--- 等待 90s 让设备注册与指标上报 ---'
sleep 90
ksi "helm list -n $NS | tail -1; kubectl -n $NS get pods --no-headers | awk '{print \$3}' | sort | uniq -c"
echo "设备: $(q_dev_all) 台，target_up=2: $(q_dev_up) 台"
echo "指标 series: $(q_series)；up 异常条数: $(q_upbad)"
echo "customLabels: count({owner=\"platform\"}) = $(vmq 'count({owner="platform"})' | jq -r '.data.result[0].value[1] // 0')"
echo "app-metrics up = $(vmq "up{cluster=\"$CLUSTER\",job=\"app-metrics\"}" | jq -r '[.data.result[]?.value[1]]|join(",") // "absent"')"
echo '```'
echo "## 4. 结论"
echo '```'
echo "rc.3 主 Release 的“卸载→设备清理→重装→设备重注册→数据恢复”整链路验证结果见上表。"
echo '```'
} >>"$F"

sleep 20
assert_eq "rc3-重装后设备数" "3" "$(q_dev_all)"
assert_eq "rc3-重装后设备全部 online" "3" "$(q_dev_up)"
assert_ge "rc3-重装后指标恢复" "10000" "$(q_series)"
assert_eq "rc3-重装后 up 无异常" "0" "$(q_upbad)"
assert_eq "rc3-重装后 customLabels 生效" "1" "$([ "$(vmq 'count({owner="platform"})' | jq -r '.data.result[0].value[1] // 0')" -gt 0 ] && echo 1 || echo 0)"

echo "rc.3 卸载重装演练完成: $F"
grep -E '^..*rc3-' "$EV/results.tsv" | tail -8
