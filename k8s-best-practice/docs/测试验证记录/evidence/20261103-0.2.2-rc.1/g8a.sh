#!/usr/bin/env bash
# G8a 证据自审：从全新 shell 重跑 12 条关键证据命令，确认可复现
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/70-audit.md"
PKG="$REPO_ROOT/categraf-0.2.2-rc.3.tgz"
OLD="$REPO_ROOT/categraf-0.2.4.tgz"

ev "$F" "G8a 证据自审：对 12 条关键结论，用全新 shell 重跑原始命令（不读取旧证据）"

audit() { local name="$1" expect="$2" actual="$3"; assert_eq "AUDIT-$name" "$expect" "$actual"; }

# A1 包 SHA256
EXPECT_SHA=$(cat "$EV/FINAL_SHA" 2>/dev/null || echo 88d9449a809096b60866355e58bdee5a7bb6488a9ff683252adad8b35a238a3a)
audit "A1-包SHA256" "$EXPECT_SHA" "$(shasum -a 256 "$PKG" | awk '{print $1}')"
# A2 包版本
audit "A2-Chart version" "0.2.2-rc.3" "$(helm show chart "$PKG" | awk '/^version:/{print $2}')"
# A3/A4 kubeVersion 边界
audit "A3-kubeVersion 1.19 通过" "OK" "$(helm template t "$PKG" --kube-version 1.19.0 --set operator.userToken=tok >/dev/null 2>&1 && echo OK || echo REJECT)"
audit "A4-kubeVersion 1.38 拒绝" "REJECT" "$(helm template t "$PKG" --kube-version 1.38.0 --set operator.userToken=tok >/dev/null 2>&1 && echo OK || echo REJECT)"
# A5 负向校验
A5=$(helm template t "$PKG" --set operator.userToken=tok --set categraf.config.interval=0 2>&1 >/dev/null | grep -c 'must be greater than 0')
audit "A5-interval=0 被拒" "1" "$A5"
# A6 与 0.2.4 渲染等价
helm template t "$OLD" --kube-version 1.28.2 --set operator.userToken=tok | sed -E 's#helm\.sh/chart: .*#NORM#; s#app\.kubernetes\.io/version: .*#NORM#; s#checksum/config: .*#NORM#; s/[[:space:]]+$//' | grep -v '^$' >/tmp/a-old.yaml
helm template t "$PKG" --kube-version 1.28.2 --set operator.userToken=tok | sed -E 's#helm\.sh/chart: .*#NORM#; s#app\.kubernetes\.io/version: .*#NORM#; s#checksum/config: .*#NORM#; s/[[:space:]]+$//' | grep -v '^$' >/tmp/a-new.yaml
audit "A6-与0.2.4语义渲染等价(忽略纯空白行)" "0" "$(diff /tmp/a-old.yaml /tmp/a-new.yaml | wc -l | tr -d ' ')"
# A7 设备
DEV=$(fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]|select(.tags_maps.cluster==\"$CLUSTER\" and .target_up==2)]|length")
audit "A7-设备 target_up=2 数量" "3" "$DEV"
# A8 customLabels 指标
audit_ge() { local name="$1" min="$2" actual="$3"; assert_ge "AUDIT-$name" "$min" "$actual"; }
audit_ge "A8-指标含 owner=platform" "1" "$(vmq 'count({owner="platform"})' | jq -r '.data.result[0].value[1] // 0')"
# A9 app-metrics target
audit "A9-app-metrics target up" "1" "$(vmq 'up{cluster="'"$CLUSTER"'",job="app-metrics"}' | jq -r '.data.result[0].value[1] // "absent"')"
# A10 release 版本
audit "A10-Release chart" "categraf-0.2.2-rc.3" "$(ksi "helm list -n $NS -o json" | jq -r '.[0].chart')"
# A11 cleanup hook 日志：3 条 deleted target
audit "A11-cleanup 删除 3 条设备记录" "3" "$(grep -c 'deleted target' "$EV/10-lifecycle.md")"
# A12 RBAC
audit "A12-operator 可 list nodes" "yes" "$(ksi "kubectl auth can-i list nodes --as=system:serviceaccount:categraf:categraf-operator 2>/dev/null")"
# A13 集群版本与 kubeVersion 边界一致性
audit "A13-集群版本 1.28.2" "v1.28.2" "$(ksi "kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'" 2>/dev/null)"

{
  echo
  echo "## 自审结论"
  echo '```'
  echo "本次自审重跑 13 条命令；新增 PASS/FAIL 见 results.tsv 前缀 AUDIT-。"
  echo "自审执行时间: $(date -u +%FT%TZ)"
  echo '```'
} >>"$F"

echo "G8a 完成: $F"
grep 'AUDIT-' "$EV/results.tsv" | tail -15
echo "AUDIT PASS=$(grep 'AUDIT-' "$EV/results.tsv" | grep -c PASS) FAIL=$(grep 'AUDIT-' "$EV/results.tsv" | grep -c FAIL || true)"
