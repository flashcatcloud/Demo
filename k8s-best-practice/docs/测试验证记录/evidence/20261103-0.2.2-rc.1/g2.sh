#!/usr/bin/env bash
# G2 生命周期：卸载清理 -> 装生产版 0.2.1 -> 升级 rc.1 -> 回滚 -> 再升级
# 破坏性：会删除本 release 在 Flashcat 上的 3 个设备后重建（已获用户授权）
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/10-lifecycle.md"
VALS=/root/categraf-024-regression-values.yaml
PKG_REMOTE=/root/categraf-0.2.2-rc.1.tgz
REPO_OCI=oci://registry.flashcat.cloud/public/charts

ev "$F" "G2 lifecycle: uninstall(with cleanup hook) -> install 0.2.1 -> upgrade 0.2.2-rc.1 -> rollback -> upgrade again"

snap() { # snap <label>
  {
    echo "### $1"
    echo '```'
    echo "\$ helm list -n categraf"
    ksi "helm list -n $NS 2>&1 | tail -3"
    echo "\$ kubectl get pods -n categraf --no-headers | 统计"
    ksi "kubectl -n $NS get pods --no-headers 2>/dev/null | awk '{print \$3}' | sort | uniq -c"
    echo "\$ Flashcat 设备（cluster=${CLUSTER}）"
    fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[] | select(.tags_maps.cluster==\"$CLUSTER\") | \"  \(.ident) target_up=\(.target_up)\"" 2>/dev/null
    echo "  本集群设备数=$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length" 2>/dev/null)  全库=$(fca "/api/n9e/targets?limit=1000&p=1" | jq '[.dat.list[]]|length' 2>/dev/null)"
    echo "\$ VM count({cluster=...}) 与 up 作业"
    echo "  series=$(vmq "count({cluster=\"$CLUSTER\"})" | jq -r '.data.result[0].value[1] // "ERR"')"
    vmq "up{cluster=\"$CLUSTER\"}" | jq -r '.data.result[] | "  up=\(.value[1]) job=\(.metric.job)"' 2>/dev/null | sort | uniq -c
    echo '```'
  } >>"$F"
}

# ---------- 0. 推送包 ----------
{
  echo "## 0. 推送待测包到测试主机"
  echo '```'
  echo "\$ scp categraf-0.2.2-rc.1.tgz root@$SSH_TARGET:$PKG_REMOTE"
  push "$REPO_ROOT/categraf-0.2.2-rc.1.tgz" "$PKG_REMOTE" && echo "(scp 成功)"
  echo "\$ sha256sum（远端）"
  ksi "sha256sum $PKG_REMOTE"
  echo '```'
} >>"$F"
assert_eq "G2-远端包SHA" "88d9449a809096b60866355e58bdee5a7bb6488a9ff683252adad8b35a238a3a" "$(ksi "sha256sum $PKG_REMOTE" | awk '{print $1}')"

snap "G2-0 卸载前基线（0.2.4 rev8）"

# ---------- 1. 卸载 + 清理 Hook ----------
{
  echo "## 1. helm uninstall（观察 pre-delete cleanup hook）"
  echo '```'
  echo "\$ 后台监听 cleanup hook pod，卸载同时抓日志"
  ksi 'rm -f /root/cleanup-hook.log /root/cleanup-hook.done; nohup bash -c "for i in \$(seq 1 120); do p=\$(kubectl -n categraf get pods -l component=operator-cleanup -o name 2>/dev/null | head -1); if [ -n \"\$p\" ]; then kubectl -n categraf logs \$p --all-containers > /root/cleanup-hook.log 2>&1; kubectl -n categraf get pod \$p -o yaml > /root/cleanup-hook-pod.yaml 2>&1; echo done > /root/cleanup-hook.done; fi; sleep 1; done" >/dev/null 2>&1 &'
  echo "\$ helm uninstall $REL -n $NS"
  ksi "time helm uninstall $REL -n $NS 2>&1"
  echo
  echo "--- 等待 hook 日志落盘 ---"
  ksi "for i in \$(seq 1 60); do [ -f /root/cleanup-hook.done ] && break; sleep 1; done; ls -la /root/cleanup-hook.log 2>/dev/null; echo; echo '--- cleanup hook 日志 ---'; cat /root/cleanup-hook.log 2>/dev/null | tail -40"
  echo
  echo "--- 卸载后集群对象 ---"
  ksi "helm list -n $NS 2>&1; echo; kubectl -n $NS get pods,ds,sts,deploy,cm,secret 2>&1 | head -20; echo; kubectl get ds,sts -A 2>/dev/null | grep -i categraf || echo '(无残留 ds/sts)'"
  echo '```'
} >>"$F"

snap "G2-1 卸载后（设备应被 cleanup hook 删除）"
assert_eq "G2-卸载后本集群设备数" "0" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\")]|length")"
assert_eq "G2-卸载不影响其它集群设备" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster!=\"$CLUSTER\")]|length")"
assert_eq "G2-卸载后 release 列表为空" "0" "$(ksi "helm list -n $NS -q | wc -l" | tr -d ' ')"

# ---------- 2. 安装生产版 0.2.1 ----------
{
  echo "## 2. 安装生产版 0.2.1（从 OCI）"
  echo '```'
  echo "\$ helm upgrade --install $REL $REPO_OCI/categraf --version 0.2.1 -n $NS --create-namespace -f $VALS"
  ksi "helm upgrade --install $REL $REPO_OCI/categraf --version 0.2.1 -n $NS --create-namespace -f $VALS --timeout 300s 2>&1 | tail -12"
  echo
  echo "\$ 等待工作负载就绪"
  wait_ready
  echo
  echo "\$ helm list / kubectl get pods"
  ksi "helm list -n $NS 2>&1 | tail -3; echo; kubectl -n $NS get pods -o wide 2>&1"
  echo '```'
} >>"$F"
snap "G2-2 安装 0.2.1 后"

# 0.2.1 能力基线：无 customLabels、app-metrics 路径修复情况
{
  echo "### 2.1 0.2.1 的已知能力基线（作为对比证据）"
  echo '```'
  echo "\$ 0.2.1 node config.toml [global.labels] 段"
  ksi "kubectl -n $NS get cm categraf-config -o jsonpath='{.data.config\.toml}' | sed -n '/\[global.labels\]/,/^\[/p'"
  echo
  echo "\$ 0.2.1 cluster-scrape.yaml 的 app-metrics job（是否缺 metrics_path 默认值）"
  ksi "kubectl -n $NS get cm categraf-ksm-scrape -o jsonpath='{.data.cluster-scrape\.yaml}' | sed -n '1,40p' | grep -E 'external_labels|job_name|metrics_path|environment|owner'"
  echo
  echo "\$ VM: up{job=\"app-metrics\"}（0.2.1 的 path relabel 修复情况）"
  vmq "up{cluster=\"$CLUSTER\",job=\"app-metrics\"}" | jq -r '.data.result[]? | "  up=\(.value[1]) instance=\(.metric.instance) service=\(.metric.service // "-")"' 2>/dev/null || echo '  (无数据)'
  echo '```'
} >>"$F"

# ---------- 3. 升级到 0.2.2-rc.1 ----------
REV_021=$(ksi "helm list -n $NS -o json" | jq -r '.[0].revision')
{
  echo "## 3. 从 0.2.1 升级到 0.2.2-rc.1（真实升级路径）"
  echo '```'
  echo "升级前 revision=$REV_021"
  echo "\$ helm upgrade $REL $PKG_REMOTE -n $NS -f $VALS --timeout 300s"
  ksi "time helm upgrade $REL $PKG_REMOTE -n $NS -f $VALS --timeout 300s 2>&1 | tail -12"
  echo
  echo "\$ helm history（末 4 行）"
  ksi "helm history $REL -n $NS | tail -4"
  echo
  echo "\$ 等待工作负载就绪"
  wait_ready
  echo
  echo "\$ kubectl get pods -o wide"
  ksi "kubectl -n $NS get pods -o wide 2>&1"
  echo "\$ helm get values 是否保持（脱敏）"
  ksi "helm get values $REL -n $NS -o yaml" | sed -E 's/(userToken|password):.*/\1: <REDACTED>/I'
  echo '```'
} >>"$F"
snap "G2-3 升级到 rc.1 后"

# ---------- 4. 回滚到 0.2.1 再升回 rc.1 ----------
{
  echo "## 4. helm rollback 回 0.2.1，再升级回 rc.1"
  echo '```'
  echo "\$ helm rollback $REL $REV_021 -n $NS"
  ksi "time helm rollback $REL $REV_021 -n $NS --timeout 300s 2>&1 | tail -8"
  echo
  echo "\$ 回滚后状态"
  ksi "helm list -n $NS 2>&1 | tail -3; kubectl -n $NS get pods --no-headers 2>&1 | wc -l"
  echo
  echo "\$ 再升级回 rc.1"
  ksi "time helm upgrade $REL $PKG_REMOTE -n $NS -f $VALS --timeout 300s 2>&1 | tail -8"
  wait_ready
  echo
  echo "\$ 最终状态"
  ksi "helm list -n $NS 2>&1 | tail -3"
  echo '```'
} >>"$F"
snap "G2-4 回滚并再次升级后（最终态 rc.1）"

# ---------- 汇总 ----------
{
  echo "## 5. 汇总"
  echo '```'
  echo "revision 轨迹:"
  ksi "helm history $REL -n $NS | tail -6"
  echo
  echo "最终设备:"
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r ".dat.list[] | select(.tags_maps.cluster==\"$CLUSTER\") | \"  \(.ident) target_up=\(.target_up) group_names=\(.group_names|tostring)\""
  echo '```'
} >>"$F"

echo "G2 完成: $F"
grep -E 'FAIL' "$EV/results.tsv" | tail -10 || echo "无 FAIL"
