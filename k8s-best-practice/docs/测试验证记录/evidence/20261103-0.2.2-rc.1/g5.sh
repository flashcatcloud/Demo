#!/usr/bin/env bash
# G5 韧性与自愈：删除各类 Pod 后自动重建、设备与指标恢复
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/40-resilience.md"
ev "$F" "G5 resilience：逐类删除 Pod，记录重建耗时与恢复证据"

t0=$(date +%s)
pod_of() { ksi "kubectl -n $NS get pods -l $1 -o name 2>/dev/null | head -1 | sed 's|pod/||'"; }
ts_of() { ksi "kubectl -n $NS get pods -l $1 -o jsonpath='{.items[0].metadata.creationTimestamp}' 2>/dev/null"; }
wait_pod_ready() { # wait_pod_ready <label_selector> <old_pod>
  local sel="$1" old="$2" i
  for i in $(seq 1 90); do
    local now; now=$(ksi "kubectl -n $NS get pods -l $sel --no-headers 2>/dev/null | awk '\$2==\"1/1\"{print \$1}' | head -1")
    if [ -n "$now" ] && [ "$now" != "$old" ]; then echo "$now"; return 0; fi
    sleep 2
  done
  echo "TIMEOUT"; return 1
}
dev_up() { fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")|\"\(.ident)=\(.target_up)\"" | sort | tr '\n' ' '; }

run_case() { # run_case <名称> <selector>
  local name="$1" sel="$2"
  local start old oldts new
  old=$(pod_of "$sel"); oldts=$(ts_of "$sel")
  start=$(date +%s)
  {
    echo "## $name"
    echo '```'
    echo "重建前 Pod: ${old:-无}"
    echo "\$ kubectl -n $NS delete pod $old --wait=false"
    ksi "kubectl -n $NS delete pod $old --wait=false 2>&1"
    echo '```'
  } >>"$F"
  # StatefulSet 会复用 Pod 名，因此以 creationTimestamp 变化 + Ready 作为重建判据
  new=""
  for i in $(seq 1 90); do
    cur_ts=$(ts_of "$sel")
    ready=$(ksi "kubectl -n $NS get pods -l $sel --no-headers 2>/dev/null | awk '\$2==\"1/1\"{print \$1}' | head -1")
    if [ -n "$ready" ] && [ -n "$cur_ts" ] && [ "$cur_ts" != "$oldts" ]; then new="$ready"; break; fi
    sleep 2
  done
  [ -z "$new" ] && new="TIMEOUT"
  local cost=$(( $(date +%s) - start ))
  {
    echo '```'
    echo "重建后 Pod: ${new}（耗时 ${cost}s）"
    echo "\$ kubectl -n $NS get pods -l $sel -o wide"
    ksi "kubectl -n $NS get pods -l $sel -o wide"
    echo '```'
  } >>"$F"
  assert_eq "G5-${name}-Pod 重建" "ok" "$( [ "$new" != "TIMEOUT" ] && echo ok || echo timeout )"
  echo "$cost" >"/tmp/g5-cost-$name.txt"
}

# 1) Node Agent
run_case "5.1 删除 Node Agent Pod" "component=categraf"
sleep 20
{
  echo '```'
  echo "\$ 30s 后设备状态: $(dev_up)"
  echo "\$ 30s 后 node 指标 2m 内 series: $(vmq 'count(count_over_time(node_cpu_seconds_total[2m]))' | jq -r '.data.result[0].value[1] // "0"')"
  echo '```'
} >>"$F"
assert_eq "G5-5.1-设备仍 3 台 target_up=2" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\" and .target_up==2)]|length")"

# 2) KSM Agent
run_case "5.2 删除 KSM Agent Pod" "component=categraf-ksm"
sleep 30
{
  echo '```'
  echo "\$ 设备: $(dev_up)"
  echo "\$ up{job=\"kube-state-metrics\"} = $(vmq 'up{job="kube-state-metrics"}' | jq -r '.data.result[0].value[1] // "absent"')"
  echo '```'
} >>"$F"

# 3) Operator（验证重新选主）
old_lease_before=$(ksi "kubectl -n $NS get lease 2>/dev/null | grep -i categraf | awk '{print \$1}'" || true)
run_case "5.3 删除 Operator Pod（重新选主）" "component=operator"
sleep 25
{
  echo '```'
  echo '--- Lease 状态 ---'
  ksi "kubectl -n $NS get lease -o wide 2>/dev/null | grep -i categraf || echo '(无 lease)'"
  echo '--- operator 启动日志（leader 相关） ---'
  ksi "kubectl -n $NS logs -l component=operator --tail=200 2>/dev/null | grep -iE 'leader|lease|starting|ready' | tail -10"
  echo '```'
} >>"$F"
assert_eq "G5-5.3-operator 重建后 Ready" "1" "$(ksi "kubectl -n $NS get pods -l component=operator --no-headers | grep -c '1/1  *Running'")"

# 4) Kube-State-Metrics
run_case "5.4 删除 kube-state-metrics Pod" "app.kubernetes.io/name=kube-state-metrics"
sleep 40
{
  echo '```'
  echo "\$ up{job=\"kube-state-metrics\"} = $(vmq 'up{job="kube-state-metrics"}' | jq -r '.data.result[0].value[1] // "absent"')"
  echo "\$ kube_pod_info 2m 内 series = $(vmq 'count(count_over_time(kube_pod_info[2m]))' | jq -r '.data.result[0].value[1] // "0"')"
  echo '```'
} >>"$F"
assert_eq "G5-5.4-KSM target 恢复" "1" "$(vmq 'up{job="kube-state-metrics"}' | jq -r '.data.result[0].value[1] // "absent"')"

{
  echo "## 汇总：重建耗时"
  echo '```'
  for f in /tmp/g5-cost-*.txt; do [ -f "$f" ] && echo "  $(basename "$f" .txt | sed 's/g5-cost-//'): $(cat "$f")s"; done
  echo "总耗时: $(( $(date +%s) - t0 ))s"
  echo '```'
} >>"$F"

echo "G5 完成: $F"
echo "PASS=$(grep -c PASS "$EV/results.tsv") FAIL=$(grep -c FAIL "$EV/results.tsv" || true)"
grep FAIL "$EV/results.tsv" | tail -5 || echo "无 FAIL"
