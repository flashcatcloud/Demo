#!/usr/bin/env bash
# C9 补充：多 Release 场景下第二个 Release 的 Agent 为何未注册设备（抓 Pod 状态与日志）
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/35-multi-release-devices.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.1.tgz
RG=/root/categraf-rg-values.yaml
ev "$F" "多 Release 并存：第二个 Release 的 Agent Pod 状态、设备注册情况与日志"
# 生成并推送 rg values（含 token，仅存在于测试机）
TOKEN=$(security find-generic-password -s flashcat-test-token -a test -w)
cat >/tmp/categraf-rg-values.yaml <<YAML
categraf:
  clusterName: k8s-flashcat-test-20261029-rg
  customLabels:
    environment: test
    owner: platform
nodeCategraf:
  hostname: "\${cluster}-\$hostname"
operator:
  enabled: true
  userToken: "$TOKEN"
YAML
push /tmp/categraf-rg-values.yaml "$RG"; rm -f /tmp/categraf-rg-values.yaml
rgdev(){ fca "/api/n9e/targets?limit=1000&p=1" | jq '[.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))]|length'; }
{
echo "## 安装 categraf-rg（ns=categraf-rg）"; echo '```'
ksi "helm upgrade --install categraf-rg $PKG -n categraf-rg --create-namespace -f $VALS -f $RG --timeout 240s 2>&1 | tail -3"
echo '--- Pod 状态（等待 30s）---'; sleep 30
ksi "kubectl -n categraf-rg get pods -o wide 2>&1; echo; kubectl -n categraf-rg get ds,sts,deploy 2>&1"
echo '--- Pod 事件/重启原因 ---'
ksi "kubectl -n categraf-rg describe pods 2>/dev/null | grep -E 'Name:|State:|Reason:|Message:|Restart Count|warning|Warning' | head -30"
echo '--- Node Agent 日志（若启动）---'
ksi "kubectl -n categraf-rg logs -l component=categraf --tail=40 2>&1 | head -40"
echo '--- 等待到 90s 再查设备 ---'; sleep 60
echo "rg 设备数 = $(rgdev)"
fca "/api/n9e/targets?limit=1000&p=1" | jq -r '.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))|"  \(.ident) cluster=\(.tags_maps.cluster) up=\(.target_up)"'
echo '```'
} >>"$F"
{
echo "## 卸载并清理"; echo '```'
ksi "helm uninstall categraf-rg -n categraf-rg --timeout 600s 2>&1 | tail -2"
sleep 20
echo "卸载后 rg 设备数 = $(rgdev)"
ksi "kubectl delete namespace categraf-rg --timeout=120s >/dev/null 2>&1"
echo '```'
} >>"$F"
echo "c9mini 完成: $F"
