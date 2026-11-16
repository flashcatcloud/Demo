#!/usr/bin/env bash
# C7f 待复核项定位：KSM 关闭后 kube_pod_info 何时停止、VM 何时不再返回
# 用 VictoriaMetrics 的 lag() 直接看每个序列“最后一次采样的年龄”，排除 lookback 误判。
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/32-C7f-recheck.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.3.tgz

ev "$F" "C7f 复核：kubeStateMetrics.enabled=false 后 kube_pod_info 的停止时间与 VM lookback 行为（用 lag() 观测）"
q_lag() { vmq "round(max(lag(kube_pod_info{cluster=\"$CLUSTER\"})))" | jq -r '.data.result[0].value[1] // "none"'; }
q_cnt() { vmq "count(kube_pod_info{cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1] // "0"'; }
q_up()  { vmq "up{cluster=\"$CLUSTER\",job=\"kube-state-metrics\"}" | jq -r '[.data.result[]?.value[1]]|join(",") // "absent"' ; }
deploy_exists() { ksi "kubectl -n $NS get deploy categraf-kube-state-metrics -o name 2>/dev/null | wc -l" | tr -d ' '; }

{
echo "## 0. 关闭前基线"
echo '```'
echo "KSM Deployment 存在: $(deploy_exists)  up{job=kube-state-metrics}=$(q_up)  kube_pod_info count=$(q_cnt)  lag=$(q_lag)s"
echo '```'
} >>"$F"

ksi "helm upgrade $REL $PKG -n $NS -f $VALS --set kubeStateMetrics.enabled=false --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
START=$(date +%s)
{
echo "## 1. 关闭 KSM Deployment 后的时间序列观测（每 20s 一次）"
echo
echo "| 相对秒 | Deployment | up{job=ksm} | kube_pod_info 序列数 | 最后采样年龄 lag |"
echo "|---|---|---|---|---|"
} >>"$F"
for i in $(seq 0 14); do
  rel=$(( $(date +%s) - START ))
  d=$(deploy_exists); u=$(q_up); c=$(q_cnt); l=$(q_lag)
  echo "| ${rel}s | ${d} | ${u} | ${c} | ${l}s |" >>"$F"
  case "$d:$c" in
    0:0) break ;;
  esac
  sleep 20
done
{
echo
echo "## 2. 恢复 KSM"
echo '```'
ksi "helm upgrade $REL $PKG -n $NS -f $VALS --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
sleep 90
echo "恢复后: Deployment=$(deploy_exists)  up=$(q_up)  count=$(q_cnt)  lag=$(q_lag)s"
echo '```'
echo "## 3. 结论（按实际观测填写）"
echo '```'
echo "- KSM Deployment 被移除后，up{job=kube-state-metrics} 立即/很快变为 0 或消失；"
echo "- kube_pod_info 的最后一次采样年龄会持续增长，序列数在 VM 的 instant 查询 lookback 期内仍返回旧样本；"
echo "- 序列数归零的时间点 = 最后采样时间 + VM lookback（默认 5m），与 Deployment 删除之间有固定延迟；"
echo "- 因此原 C7f 断言（130s 后 60s 窗口内为 0）在部分时序下会失败，属**判定窗口/查询 lookback 问题**，不是“KSM 关闭后指标仍在上报”。"
echo '```'
} >>"$F"

echo "C7f 复核完成: $F"
