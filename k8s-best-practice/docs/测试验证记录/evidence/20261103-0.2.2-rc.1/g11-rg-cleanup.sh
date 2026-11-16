#!/usr/bin/env bash
# 多 Release 卸载清理（干净重来一遍，验证 cleanup hook 的设备删除范围，并清掉残留设备）
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/36-multi-release-final.md"
VALS=/root/categraf-024-regression-values.yaml
PKG=/root/categraf-0.2.2-rc.1.tgz
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
  echo; echo '## 干净重来：安装 -> 卸载（验证 cleanup hook 在第二个 Release 上的删除范围）'; echo '```'
  ksi "helm list -A 2>/dev/null | grep categraf-rg || echo '(无残留 release)'"
  ksi "helm upgrade --install categraf-rg $PKG -n categraf-rg --create-namespace -f $VALS -f /root/categraf-rg-values.yaml --timeout 240s 2>&1 | tail -3"
  echo '--- 等待工作负载 ---'
  ksi "kubectl -n categraf-rg wait --for=condition=Available deploy --all --timeout=180s 2>&1 | tail -2"
  echo "安装后 rg 设备数=$(rgcount)"
  echo '--- 卸载（抓 hook 日志）---'
  ksi "rm -f /root/rg-hook.log; nohup bash -c 'for i in \$(seq 1 90); do p=\$(kubectl -n categraf-rg get pods -l component=operator-cleanup -o name 2>/dev/null | head -1); if [ -n \"\$p\" ]; then kubectl -n categraf-rg logs \$p > /root/rg-hook.log 2>&1; break; fi; sleep 1; done' >/dev/null 2>&1 &"
  ksi "helm uninstall categraf-rg -n categraf-rg --timeout 600s 2>&1 | tail -3"
  sleep 45
  echo '--- hook 日志（最后 12 行）---'
  ksi "tail -12 /root/rg-hook.log 2>/dev/null || echo '(未捕获到 hook 日志)'"
  echo "卸载后 rg 设备数=$(rgcount)  主集群设备数=$(maincount)"
  echo '```'
} >>"$F"
assert_eq "G10b-rg 卸载后本集群设备清理" "0" "$(rgcount)"
assert_eq "G10b-主集群设备不受影响" "3" "$(maincount)"
ksi "kubectl delete namespace categraf-rg --timeout=120s >/dev/null 2>&1"
echo "G11 完成"; grep 'G10b-' "$EV/results.tsv"
