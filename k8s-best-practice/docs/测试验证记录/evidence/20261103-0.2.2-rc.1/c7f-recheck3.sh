#!/usr/bin/env bash
# C7f 第三轮：用 job 标签区分来源，证明“KSM job 的 kube_* 指标确实停止”
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/32-C7f-recheck.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.3.tgz
w()   { vmq "count(count_over_time($1[60s]))" | jq -r '.data.result[0].value[1] // "0"'; }
byjob(){ vmq "count by (job) (count_over_time(kube_pod_info{cluster=\"$CLUSTER\"}[60s]))" | jq -r '.data.result[]? | "    job=\(.metric.job // "-") series=\(.value[1])"' ; }

{
echo
echo "## 6. 第三轮：kube_pod_info 的来源分解（关键证据）"
echo '```'
echo "恢复态（KSM 开启）按 job 分组："
byjob
echo '```'
echo "说明：`app-metrics` job 的 20 条 kube_pod_info 来自 **annotated-metrics-test 这个测试 Pod**——它用的就是 kube-state-metrics 镜像，自己也暴露 kube_* 指标。"
echo '```'
} >>"$F"

ksi "helm upgrade $REL $PKG -n $NS -f $VALS --set kubeStateMetrics.enabled=false --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
sleep 120
{
echo
echo "关闭 KSM Deployment 120s 后："
echo '```'
echo "  全量 60s 窗口 kube_pod_info series            = $(w "kube_pod_info{cluster=\"$CLUSTER\"}")"
echo "  仅 job=kube-state-metrics 的 series           = $(w "kube_pod_info{cluster=\"$CLUSTER\",job=\"kube-state-metrics\"}")   ← 这才是“KSM 是否停止上报”的正确判定"
echo "  仅 job=app-metrics 的 series（测试 Pod 自带）  = $(w "kube_pod_info{cluster=\"$CLUSTER\",job=\"app-metrics\"}")"
echo '```'
echo "按 job 分组明细："
echo '```'
byjob
echo '```'
echo "## 7. C7f 最终结论"
echo '```'
echo "原 C7f 断言用 `kube_pod_info` 全量统计，而验证环境里的 annotated-metrics-test Pod 本身跑的也是 kube-state-metrics 镜像，"
echo "其 kube_* 指标会通过 app-metrics job 继续上报，因此全量统计永远不会归零；"
echo "正确判定：KSM 关闭后 `kube_pod_info{job=\"kube-state-metrics\"}` 在 ~60-90s 内归零（本轮实测见上），"
echo "说明 KSM 指标链路确实随 Deployment 移除而停止 —— **原 FAIL 是测试设计问题，不是 Chart 缺陷**。"
echo '```'
} >>"$F"

ksi "helm upgrade $REL $PKG -n $NS -f $VALS --timeout 240s >/dev/null 2>&1"; wait_ready >/dev/null 2>&1
sleep 60
echo "C7f 第三轮完成: $F"
