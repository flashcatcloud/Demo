#!/usr/bin/env bash
# G0 环境基线快照（只读）
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

F="$EV/00-baseline.md"
ev "$F" "G0 baseline: helm/kubectl/Flashcat/VM 全量只读快照"

{
  echo "## A. 时间与工具版本"
  echo '```'
  echo "local: $(date +%FT%T%z) / host: $(ksi 'date +%FT%T%z')"
  echo "local helm: $(helm version --short)"
  echo "local kubectl client: $(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | tr -d ' ')"
  echo "remote helm: $(ksi 'helm version --short')"
  echo "remote kubectl: $(ksi 'kubectl version --client=true -o yaml 2>/dev/null | grep gitVersion | head -1 | tr -d " "')"
  echo "package: $(shasum -a 256 "$REPO_ROOT/categraf-0.2.2-rc.1.tgz" | awk '{print $1}')  ($(ls -l "$REPO_ROOT/categraf-0.2.2-rc.1.tgz" | awk '{print $5}') bytes)"
  echo '```'
} >>"$F"

{
  echo "## B. 当前 Release 状态（改装前）"
  echo '```'
  echo '$ helm list -n categraf -o json'
  ksi "helm list -n categraf -o json 2>/dev/null" | python3 -m json.tool 2>/dev/null | head -40
  echo
  echo '$ helm history categraf -n categraf'
  ksi "helm history $REL -n $NS"
  echo '```'
} >>"$F"

{
  echo "## C. 当前 values（token 脱敏）"
  echo '```yaml'
  ksi "helm get values $REL -n $NS -o yaml" | sed -E 's/(userToken|password):.*/\1: <REDACTED>/I'
  echo '```'
} >>"$F"

{
  echo "## D. 集群与工作负载"
  echo '```'
  echo '$ kubectl get nodes -o wide'
  ksi "kubectl get nodes -o wide"
  echo
  echo '$ kubectl get all -n categraf -o wide'
  ksi "kubectl -n $NS get all -o wide"
  echo
  echo '$ kubectl -n categraf get pvc,lease,endpoints'
  ksi "kubectl -n $NS get pvc,lease,endpoints 2>&1 | head -20; kubectl get lease -A | grep -i categraf"
  echo '```'
} >>"$F"

{
  echo "## E. 当前 ConfigMap（0.2.4 渲染结果，作为对照）"
  echo '```'
  echo '$ kubectl -n categraf get cm categraf-node-config -o jsonpath={.data.config\.toml}'
  ksi "kubectl -n $NS get cm categraf-config -o jsonpath='{.data.config\.toml}' 2>/dev/null || kubectl -n $NS get cm | head"
  echo
  echo '--- ksm config.toml ---'
  ksi "kubectl -n $NS get cm categraf-ksm-config -o jsonpath='{.data.config\.toml}'"
  echo
  echo '--- cluster-scrape.yaml (job_name 列表) ---'
  ksi "kubectl -n $NS get cm categraf-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}' | grep -E 'job_name|scrape_interval'"
  echo '--- ConfigMap 清单 ---'
  ksi "kubectl -n $NS get cm -o name"
  echo '```'
} >>"$F"

{
  echo "## F. Flashcat 设备基线"
  echo '```'
  echo '$ fcapi /api/n9e/targets?limit=1000&p=1 | jq (cluster=本集群)'
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[] | select(.tags_maps.cluster==\"$CLUSTER\") | \"\(.id)\t\(.ident)\ttarget_up=\(.target_up)\tagent=\(.agent_version)\tgroup_names=\(.group_names|tostring)\tbeat_time=\(.beat_time)\tupdate_at=\(.update_at)\""
  echo
  echo "本集群设备数: $(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
  echo "全库设备数: $(fca "/api/n9e/targets?limit=1000&p=1" | jq '[.dat.list[]]|length')"
  echo '```'
} >>"$F"

{
  echo "## G. VictoriaMetrics 指标基线"
  echo '```'
  echo "count({cluster=\"$CLUSTER\"}) = $(vmq "count({cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1] // "ERR"')"
  echo "count(up) 全库 = $(vmq 'count(up)' | jq -r '.data.result[0].value[1] // "ERR"')"
  echo
  echo 'up{cluster=本集群}:'
  vmq "up{cluster=\"$CLUSTER\"}" | jq -r '.data.result[] | "  up=\(.value[1])  job=\(.metric.job)  instance=\(.metric.instance)  pod=\(.metric.pod // "-")"'
  echo
  echo '关键指标族存在性（count）:'
  for m in node_cpu_seconds_total container_cpu_usage_seconds_total kube_pod_info kube_node_info cpu_usage_active kube_node_status_condition diskio_read_bytes_total; do
    printf '  %-38s %s\n' "$m" "$(vmq "count($m)" | jq -r '.data.result[0].value[1] // "无"')"
  done
  echo '```'
} >>"$F"

{
  echo "## H. 控制平面监听参数（决定 controlPlane 采集用例预期）"
  echo '```'
  for c in kube-apiserver kube-controller-manager kube-scheduler etcd; do
    echo "--- $c ---"
    ksi "kubectl get pod -n kube-system -l component=$c -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null | tr ' ' '\n' | grep -E 'bind-address|listen-metrics-urls|listen-client-urls|secure-port' || echo '(无匹配)'; echo"
  done
  echo '--- 集群插件 / 网络 ---'
  ksi "kubectl get pods -n kube-system -o name | sed 's|pod/||' | sed 's/-[a-z0-9]*-[a-z0-9]*\$//' | sort -u"
  echo '```'
} >>"$F"

{
  echo "## I. 测试主机上的包与临时文件"
  echo '```'
  ksi "ls -la /root/*.tgz /root/*.yaml 2>/dev/null; echo; ls -la /root/categraf-rg 2>/dev/null || echo '无 categraf-rg 目录'"
  echo '```'
} >>"$F"

echo "G0 完成: $F"
