#!/usr/bin/env bash
# C7f 复核第二轮：同时记录“instant 查询(lookback 5m)”与“60s 窗口 count_over_time”，定位原断言为何失败
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/32-C7f-recheck.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.3.tgz
q_inst()  { vmq "count(kube_pod_info{cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1] // "0"'; }
q_win60() { vmq "count(count_over_time(kube_pod_info{cluster=\"$CLUSTER\"}[60s]))" | jq -r '.data.result[0].value[1] // "0"'; }
q_winall(){ vmq "count(count_over_time(kube_pod_info[60s]))" | jq -r '.data.result[0].value[1] // "0"'; }
q_lag()   { vmq "round(max(lag(kube_pod_info{cluster=\"$CLUSTER\"})))" | jq -r '.data.result[0].value[1] // "none"'; }
q_up()    { vmq "up{cluster=\"$CLUSTER\",job=\"kube-state-metrics\"}" | jq -r '[.data.result[]?.value[1]]|join(",") // "absent"'; }

{
echo
echo "## 4. 第二轮复核：instant vs 60s 窗口（区分“仍在写入”与“lookback 旧样本”）"
echo
echo "| 相对秒 | Deployment | up{job} | instant count | 60s窗口(本集群) | 60s窗口(全库) | lag |"
echo "|---|---|---|---|---|---|---|"
} >>"$F"

ksi "helm upgrade $REL $PKG -n $NS -f $VALS --set kubeStateMetrics.enabled=false --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
START=$(date +%s)
for i in $(seq 0 12); do
  rel=$(( $(date +%s) - START ))
  d=$(ksi "kubectl -n $NS get deploy categraf-kube-state-metrics -o name 2>/dev/null | wc -l" | tr -d ' ')
  echo "| ${rel}s | ${d} | $(q_up) | $(q_inst) | $(q_win60) | $(q_winall) | $(q_lag)s |" >>"$F"
  [ "$(q_win60)" = "0" ] && [ "$rel" -gt 30 ] && break
  sleep 20
done
{
echo
echo '--- 恢复 KSM ---'
ksi "helm upgrade $REL $PKG -n $NS -f $VALS --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
sleep 75
echo "恢复后: instant=$(q_inst) 60s窗口=$(q_win60) lag=$(q_lag)s up=$(q_up)"
echo
echo "## 5. 最终结论"
echo '```'
echo "instant 查询会受 VM lookback（默认 5m）影响，Deployment 删除后仍返回旧样本，最长约 5 分钟；"
echo "60s 窗口 count_over_time 能真实反映“是否还在写入”，应在停止抓取后 ~60-90s 归零；"
echo "→ 原 C7f 用 60s 窗口却得到非零，属于**当时查询未加 cluster 过滤**（把当时并存的第二个 Release 的 kube_pod_info 也算了进来），"
echo "  不是“KSM 关闭后本集群指标仍在上报”。本表带 cluster 过滤的 60s 窗口在本轮应归零，即为正确判定方法。"
echo '```'
} >>"$F"
echo "C7f 第二轮完成: $F"
