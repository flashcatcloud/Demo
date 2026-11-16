#!/usr/bin/env bash
# G3 核心数据链路（rc.1 运行态）：设备心跳 / 指标落库 / 日志健康 / 渲染态配置
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/20-datalink.md"

ev "$F" "G3 datalink: 设备+心跳、VM 指标落库、agent 日志、rc.1 渲染配置"

# ---------- 3.1 设备与心跳 ----------
{
  echo "## 3.1 Flashcat 设备与心跳"
  echo '```'
  echo '$ fcapi /api/n9e/targets?limit=1000（原始响应的本集群部分存 20-devices.json）'
  fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]" >"$EV/20-devices.json"
  cat "$EV/20-devices.json" | jq -r '.[] | "id=\(.id) ident=\(.ident) target_up=\(.target_up) group_id=\(.group_id) group_names=\(.group_names|tostring) agent=\(.agent_version) beat_time=\(.beat_time)"'
  echo
  NOW=$(date +%s)
  echo "当前 epoch=$NOW"
  cat "$EV/20-devices.json" | jq -r --argjson now "$NOW" '.[] | "\(.ident): beat_age=\($now - .beat_time)s  update_age=\($now - .update_at)s"'
  echo '```'
} >>"$F"
assert_eq "3.1-设备数" "3" "$(jq 'length' "$EV/20-devices.json")"
assert_eq "3.1-全部 target_up=2" "3" "$(jq '[.[]|select(.target_up==2)]|length' "$EV/20-devices.json")"
NOW=$(date +%s); MAXBEAT=$(jq -r '[.[].beat_time]|max' "$EV/20-devices.json"); AGE=$((NOW-MAXBEAT)); [ "$AGE" -lt 0 ] && AGE=0
assert_ge "3.1-心跳年龄<=60s(age=${AGE}s)" "0" "$((60-AGE))" "beat_time 距今不超过 60s"
assert_eq "3.1-heartbeatGid=2 生效(group_objs)" "2" "$(jq -r '[.[]|select(.ident|test("node"))][0].group_objs[0].id' "$EV/20-devices.json")"
assert_eq "3.1-agent 版本" "ent-v0.5.32" "$(jq -r '.[0].agent_version' "$EV/20-devices.json")"
assert_eq "3.1-customLabels owner 落库" "platform" "$(jq -r '.[0].tags_maps.owner // "缺失"' "$EV/20-devices.json")"
assert_eq "3.1-customLabels environment 落库" "test" "$(jq -r '.[0].tags_maps.environment // "缺失"' "$EV/20-devices.json")"

# ---------- 3.2 指标落库 ----------
{
  echo "## 3.2 VictoriaMetrics 指标落库（instant 查询 lookback=5m，presence 即新鲜）"
  echo '```'
  echo "查询时间: $(date +%FT%T%z)"
  echo "count({cluster=\"$CLUSTER\"}) = $(vmq "count({cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1] // "ERR"')"
  echo "count(up{cluster})          = $(vmq "count(up{cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1] // "ERR"')"
  echo
  echo 'up 明细（应全为 1）:'
  vmq "up{cluster=\"$CLUSTER\"}" | tee "$EV/21-up.json" | jq -r '.data.result[] | "  up=\(.value[1])  job=\(.metric.job)  instance=\(.metric.instance)  pod=\(.metric.pod // "-")  service=\(.metric.service // "-")"'
  echo
  echo '关键指标族:'
  for m in node_cpu_seconds_total node_memory_MemAvailable_bytes container_cpu_usage_seconds_total container_memory_working_set_bytes kube_pod_info kube_node_info kube_node_status_condition cpu_usage_active mem_used_percent disk_used_percent net_bits_recv process_open_fds kube_proxy_sync_proxy_rules_duration_seconds coredns_dns_requests_total; do
    printf '  %-46s %s\n' "$m" "$(vmq "count($m)" | jq -r '.data.result[0].value[1] // "无"')"
  done
  echo
  echo '各节点上报（node_cpu_seconds_total by instance/host）:'
  vmq "count by (instance) (node_cpu_seconds_total)" | jq -r '.data.result[] | "  instance=\(.metric.instance // "-") series=\(.value[1])"'
  echo '```'
} >>"$F"
assert_eq "3.2-up 全为 1" "0" "$(jq '[.data.result[]|select(.value[1]!="1")]|length' "$EV/21-up.json")"
assert_ge "3.2-series 总量" "12000" "$(vmq "count({cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1]')"
assert_ge "3.2-node_exporter 节点数" "2" "$(vmq 'count by (instance) (node_cpu_seconds_total)' | jq -r '[.data.result[]]|length')"
assert_ge "3.2-kube-state-metrics 指标" "1" "$(vmq 'count(kube_pod_info)' | jq -r '.data.result[0].value[1] // 0')"
assert_eq "3.2-app-metrics target up" "1" "$(jq -r '[.data.result[]|select(.metric.job=="app-metrics")][0].value[1] // "absent"' "$EV/21-up.json")"
assert_ge "3.2-cadvisor 容器指标" "1" "$(vmq 'count(container_cpu_usage_seconds_total)' | jq -r '.data.result[0].value[1] // 0')"

# ---------- 3.3 rc.1 渲染态配置 ----------
{
  echo "## 3.3 rc.1 运行态 config.toml 与 scrape 配置"
  echo '```'
  echo '--- Node Agent config.toml ---'
  ksi "kubectl -n $NS get cm categraf-config -o jsonpath='{.data.config\.toml}'"
  echo
  echo '--- KSM Agent config.toml ---'
  ksi "kubectl -n $NS get cm categraf-ksm-config -o jsonpath='{.data.config\.toml}' | head -30"
  echo
  echo '--- cluster-scrape.yaml: external_labels + job 列表 ---'
  ksi "kubectl -n $NS get cm categraf-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}' | grep -nE 'scrape_interval|external_labels|cluster:|environment:|owner:|job_name|metrics_path'"
  echo
  echo '--- Node Agent 关键 pod 规格 ---'
  ksi "kubectl -n $NS get ds categraf -o jsonpath='{.spec.template.spec.containers[0].env}'"
  echo
  echo '--- 节点 Agent 实际运行节点 ---'
  ksi "kubectl -n $NS get pods -l component=categraf -o wide"
  echo '```'
} >>"$F"

# ---------- 3.4 日志健康 ----------
L="$EV/22-logs.txt"
ev "$L" "G3 日志健康检查：最近 300 行，grep error/fail/refused/401/tail command"
for sel in "component=categraf" "component=categraf-ksm" "component=operator"; do
  {
    echo "### $sel"
    echo '```'
    P=$(ksi "kubectl -n $NS get pods -l $sel -o name 2>/dev/null | head -1")
    echo "pod=${P:-无}"
    if [ -n "${P:-}" ]; then
      ksi "kubectl -n $NS logs -p ${P:-} --tail=300 2>/dev/null; kubectl -n $NS logs ${P} --tail=300 2>/dev/null" >"/tmp/log-$(echo "$sel"|tr '=' '-').txt"
      echo "--- 命中行（error|fail|refused|401|tail command）---"
      grep -iE 'error|fail|refused|401|tail command' "/tmp/log-$(echo "$sel"|tr '=' '-').txt" | tail -20 || echo '(无命中)'
      echo "--- 行数: $(wc -l <"/tmp/log-$(echo "$sel"|tr '=' '-').txt") ---"
    fi
    echo '```'
  } >>"$L"
done
# syslog 已知问题专项：不宣称已修复，只记录当前命中数（结论见 FINDINGS.md 已知问题 1）
SYSLOG_CNT=$(grep -ci 'failed to execute tail command' /tmp/log-component-categraf.txt 2>/dev/null || echo 0)
echo "syslog 报错命中数（当前容器最近 300 行）: $SYSLOG_CNT —— 记录为已知问题，不作为通过项" >>"$L"
# 收集 node/operator 日志中的高位错误计数（允许心跳/网络瞬时错误，逐条人工归类后写入报告）

# ---------- 3.5 operator 健康 ----------
{
  echo "## 3.5 Operator 状态（leader lease / 探针 / 配置）"
  echo '```'
  echo '$ kubectl get lease（含 categraf 相关）'
  ksi "kubectl get lease -A 2>/dev/null | grep -i categraf || echo '(未找到 categraf lease)'"
  echo
  echo '$ operator configmap 环境变量'
  ksi "kubectl -n $NS get cm categraf-operator-config -o jsonpath='{.data}' | python3 -m json.tool"
  echo
  echo '$ operator 最近日志中的 leader 相关'
  ksi "kubectl -n $NS logs -l component=operator --tail=300 2>/dev/null | grep -iE 'leader|lease|cleanup|error' | tail -15"
  echo '```'
} >>"$F"

echo "G3 完成: $F / $L"
grep FAIL "$EV/results.tsv" | tail -5 || echo "无 FAIL"
