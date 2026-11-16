#!/usr/bin/env bash
# A.1「自动发现模式」真机验证：放开 kube-controller-manager / kube-scheduler / etcd 监听地址，
# 开启 controlPlane.enabled=true，确认 4 个 job 全部 up=1；结束后完整还原。
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/64-controlplane-a1.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2.tgz
TS=$(date +%Y%m%d-%H%M%S)
BK=/root/k8s-cp-backup-$TS
UFW_ADDED=0

q_up() { vmq "up{cluster=\"$CLUSTER\",job=\"$1\"}" | jq -r '[.data.result[]?.value[1]]|join(",") // "absent"'; }
q_cnt(){ vmq "count($1{cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1] // "0"'; }
ports(){ ksi "ss -tln 2>/dev/null | grep -E ':10257|:10259|:2381' | awk '{print \$4}' | sort -u | tr '\n' ' '"; }

restore() {
  echo '--- 还原控制平面监听地址 ---'
  ksi "cp $BK/kube-controller-manager.yaml $BK/kube-scheduler.yaml $BK/etcd.yaml /etc/kubernetes/manifests/ && echo 'manifests restored'" 2>&1
  if [ "$UFW_ADDED" = "1" ]; then
    ksi "ufw delete allow from 10.244.0.0/16 to any port 10257 proto tcp >/dev/null 2>&1; ufw delete allow from 10.244.0.0/16 to any port 10259 proto tcp >/dev/null 2>&1; ufw delete allow from 10.244.0.0/16 to any port 2381 proto tcp >/dev/null 2>&1; echo 'ufw rules removed'" 2>&1
  fi
  echo '--- 关闭 controlPlane（恢复基线 values）---'
  ksi "helm upgrade categraf $PKG -n $NS -f $VALS --timeout 300s >/dev/null 2>&1; echo helm-restored" 2>&1
  sleep 50
  echo "还原后监听: $(ports)"
  echo "还原后 controlPlane job: apiserver=$(q_up apiserver) kcm=$(q_up kube-controller-manager) sched=$(q_up kube-scheduler) etcd=$(q_up etcd)"
  ksi "kubectl get nodes --no-headers 2>&1 | awk '{print \$1,\$2}'"
}
trap restore EXIT

ev "$F" "A.1 自动发现模式真机验证：放开 KCM/scheduler bind-address 与 etcd metrics 监听，验证 4 个 controlPlane job 可采集（测试后完整还原）"

{
echo "## 0. 变更前基线"
echo '```'
echo "controlPlane.enabled（values 基线）= false（chart 默认）"
echo "监听地址: $(ports)"
echo "节点: $(ksi "kubectl get nodes --no-headers | awk '{print \$1,\$2}' | tr '\n' ' ')")"
echo "ufw: $(ksi "ufw status 2>/dev/null | head -1")"
echo '```'
} >>"$F"

{
echo "## 1. 备份并修改 Static Pod manifest"
echo '```'
ksi "mkdir -p $BK && cp /etc/kubernetes/manifests/kube-controller-manager.yaml /etc/kubernetes/manifests/kube-scheduler.yaml /etc/kubernetes/manifests/etcd.yaml $BK/ && ls -1 $BK"
echo
echo '$ 修改 bind-address / listen-metrics-urls'
ksi "sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/g' /etc/kubernetes/manifests/kube-controller-manager.yaml /etc/kubernetes/manifests/kube-scheduler.yaml; sed -i 's#--listen-metrics-urls=http://127.0.0.1:2381#--listen-metrics-urls=http://0.0.0.0:2381#' /etc/kubernetes/manifests/etcd.yaml; grep -hoE -- '--(bind-address|listen-metrics-urls)=[^ ]*' /etc/kubernetes/manifests/kube-controller-manager.yaml /etc/kubernetes/manifests/kube-scheduler.yaml /etc/kubernetes/manifests/etcd.yaml"
echo
echo '$ 等待 kubelet 重建 Static Pod（30s 后看监听）'
sleep 35
echo "监听地址: $(ports)"
echo '```'
} >>"$F"

# 防火墙：若启用则临时放通 Pod 网段
UFW_STATE=$(ksi "ufw status 2>/dev/null | head -1")
if echo "$UFW_STATE" | grep -qi active; then
  {
  echo "## 2. 防火墙（ufw active，临时放通 Pod 网段）"
  echo '```'
  ksi "ufw status verbose 2>/dev/null | head -12"
  echo
  echo '$ ufw allow from 10.244.0.0/16 to 10257/10259/2381'
  ksi "ufw allow from 10.244.0.0/16 to any port 10257 proto tcp >/dev/null 2>&1; ufw allow from 10.244.0.0/16 to any port 10259 proto tcp >/dev/null 2>&1; ufw allow from 10.244.0.0/16 to any port 2381 proto tcp >/dev/null 2>&1; ufw status 2>/dev/null | grep -E '10257|10259|2381'"
  echo '```'
  } >>"$F"
  UFW_ADDED=1
else
  {
  echo "## 2. 防火墙"
  echo '```'
  echo "ufw 未启用（${UFW_STATE}），无需放通"
  echo '```'
  } >>"$F"
fi

{
echo "## 3. 开启 controlPlane.enabled=true"
echo '```'
echo "\$ helm upgrade categraf $PKG -n $NS -f $VALS --set controlPlane.enabled=true"
ksi "helm upgrade categraf $PKG -n $NS -f $VALS --set controlPlane.enabled=true --timeout 300s 2>&1 | tail -4"
ksi "kubectl -n $NS rollout status sts categraf-ksm --timeout=240s 2>&1 | tail -1"
echo
echo '$ 渲染出的控制平面 job'
ksi "kubectl -n $NS get cm categraf-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}' | grep -E \"job_name: '(apiserver|kube-controller-manager|kube-scheduler|etcd)'\""
echo '```'
} >>"$F"

{
echo "## 4. 等待 2 个抓取周期后验证（关键结果）"
echo '```'
sleep 120
for j in apiserver kube-controller-manager kube-scheduler etcd; do
  printf '  up{job="%s"} = %s\n' "$j" "$(q_up "$j")"
done
echo
echo '--- 指标是否真的落库 ---'
echo "  apiserver_request_total            = $(q_cnt apiserver_request_total)"
echo "  workqueue_queue_duration_seconds   = $(q_cnt workqueue_queue_duration_seconds)"
echo "  scheduler_schedule_attempts_total  = $(q_cnt scheduler_schedule_attempts_total)"
echo "  etcd_server_has_leader             = $(q_cnt etcd_server_has_leader)"
echo
echo '--- KSM Agent 日志中 scrape 相关错误（应为空）---'
ksi "kubectl -n $NS logs sts/categraf-ksm --tail=400 2>/dev/null | grep -iE 'server returned HTTP status|connection refused|context deadline' | tail -5 || echo '(无)'"
echo '```'
} >>"$F"

assert_eq "A1-apiserver up=1" "1" "$(q_up apiserver)"
assert_eq "A1-kube-controller-manager up=1" "1" "$(q_up kube-controller-manager)"
assert_eq "A1-kube-scheduler up=1" "1" "$(q_up kube-scheduler)"
assert_eq "A1-etcd up=1" "1" "$(q_up etcd)"
assert_ge "A1-etcd 指标落库" "1" "$(q_cnt etcd_server_has_leader)"
assert_ge "A1-apiserver 指标落库" "1" "$(q_cnt apiserver_request_total)"

echo "A.1 验证完成（退出时自动还原）: $F"
