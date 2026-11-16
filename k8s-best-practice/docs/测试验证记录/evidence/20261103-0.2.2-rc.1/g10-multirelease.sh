#!/usr/bin/env bash
# 多 Release 并存与卸载清理范围（最终补充验证）
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/36-multi-release-final.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.1.tgz
ev "$F" "多 Release 并存：第二个 Release 的命名/RBAC/设备隔离与卸载清理范围"
TOKEN=$(security find-generic-password -s flashcat-test-token -a test -w)
cat >/tmp/rg.yaml <<YAML
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
sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q /tmp/rg.yaml root@"$SSH_TARGET":/root/categraf-rg-values.yaml
rm -f /tmp/rg.yaml
rgcount() { fca "/api/n9e/targets?limit=1000&p=1" | jq '[.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))]|length'; }
maincount() { fca "/api/n9e/targets?limit=1000&p=1" | jq "[.dat.list[]?|select(.tags_maps.cluster?==\"$CLUSTER\")]|length"; }
{
  echo '## 安装 categraf-rg'; echo '```'
  ksi "ls -l /root/categraf-rg-values.yaml"
  ksi "helm upgrade --install categraf-rg $PKG -n categraf-rg --create-namespace -f $VALS -f /root/categraf-rg-values.yaml --timeout 240s 2>&1 | tail -4"
  echo '--- 工作负载 ---'; ksi "kubectl -n categraf-rg get ds,sts,deploy -o name 2>&1 | head -8"
  echo '--- ClusterRole（应含 release-namespace 前缀，与主 Release 不冲突）---'; ksi "kubectl get clusterrole 2>/dev/null | grep -E 'categraf-rg-categraf-rg' | head -6"
  echo '--- 等待 120s 设备注册 ---'; sleep 120
  fca "/api/n9e/targets?limit=1000&p=1" | jq -r '.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))|"  \(.ident) cluster=\(.tags_maps.cluster) up=\(.target_up)"'
  echo "rg 设备数=$(rgcount)  主集群设备数=$(maincount)"
  echo '```'
  echo '## 卸载 categraf-rg（cleanup hook 只删本集群设备）'; echo '```'
  ksi "helm uninstall categraf-rg -n categraf-rg --timeout 600s 2>&1 | tail -3"
  sleep 45
  echo "卸载后 rg 设备数=$(rgcount)  主集群设备数=$(maincount)"
  echo '```'
} >"$F"
assert_eq "G10-rg 设备数" "3" "$(rgcount)"
assert_eq "G10-rg 设备 ident 含 -rg-" "3" "$(fca "/api/n9e/targets?limit=1000&p=1" | jq '[.dat.list[]?|select(.tags_maps.cluster? and (.tags_maps.cluster|test("rg$")))|select(.ident|contains("-rg-"))]|length')"
assert_eq "G10-rg 卸载后本集群设备清理" "0" "$(rgcount)"
assert_eq "G10-主集群设备不受影响" "3" "$(maincount)"
ksi "kubectl delete namespace categraf-rg --timeout=120s >/dev/null 2>&1"
echo "G10 完成: $F"; grep 'G10-' "$EV/results.tsv"
