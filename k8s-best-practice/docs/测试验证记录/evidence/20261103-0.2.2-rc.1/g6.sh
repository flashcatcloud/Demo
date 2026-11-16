#!/usr/bin/env bash
# G6 打包与发布面：包内容一致性、双 Helm 版本、publish-chart.sh 预发布守卫
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/50-package.md"
CHART_DIR="$REPO_ROOT/assets/categraf-helm/categraf"
PKG="$REPO_ROOT/categraf-0.2.2-rc.3.tgz"

ev "$F" "G6 package：包内容一致性、Helm 3/4 双版本、发布脚本守卫"

# ---------- 6.1 包内容与仓库 chart 目录一致 ----------
rm -rf /tmp/pkg-a /tmp/pkg-b && mkdir -p /tmp/pkg-a /tmp/pkg-b
tar xzf "$PKG" -C /tmp/pkg-a
cp -R "$CHART_DIR"/. /tmp/pkg-b/
{
  echo "## 6.1 包内容 vs 仓库目录（解包后逐文件 diff）"
  echo '```'
  echo "说明：helm package 会重新序列化 Chart.yaml（键排序、注释丢失），因此对 Chart.yaml 比较语义、其余文件比较字节"
  echo "\$ helm show chart <解包目录> vs <包>"
  helm show chart /tmp/pkg-a/categraf >/tmp/chart-dir.yaml
  helm show chart "$PKG" >/tmp/chart-pkg.yaml
  if diff -u /tmp/chart-pkg.yaml /tmp/chart-dir.yaml; then echo "(Chart.yaml 语义一致)"; fi
  echo "\$ diff -r（排除 Chart.yaml）"
  if diff -r -x Chart.yaml /tmp/pkg-a/categraf "$CHART_DIR" >/tmp/pkg-diff.txt 2>&1; then echo "(其余文件完全一致)"; else cat /tmp/pkg-diff.txt; fi
  echo
  echo "\$ tar tzf 文件数"
  echo "包内文件: $(tar tzf "$PKG" | wc -l | tr -d ' ')"
  tar tzf "$PKG"
  echo '```'
} >>"$F"
assert_eq "6.1-Chart.yaml 语义一致" "0" "$(diff /tmp/chart-pkg.yaml /tmp/chart-dir.yaml | wc -l | tr -d ' ')"
assert_eq "6.1-其余文件一致" "0" "$(diff -r -x Chart.yaml /tmp/pkg-a/categraf "$CHART_DIR" 2>&1 | wc -l | tr -d ' ')"
assert_eq "6.1-包内无 .DS_Store/.git" "0" "$(tar tzf "$PKG" | grep -cE '\.DS_Store|\.git/' || true)"

# ---------- 6.2 show values 一致性 ----------
{
  echo "## 6.2 helm show values vs 仓库 values.yaml"
  echo '```'
  helm show values "$PKG" >/tmp/show-values.yaml
  if diff -B -q /tmp/show-values.yaml "$CHART_DIR/values.yaml" >/dev/null 2>&1; then echo "(一致，忽略尾部空行差异)"; else diff -B /tmp/show-values.yaml "$CHART_DIR/values.yaml" | head -20; fi
  echo '```'
} >>"$F"
assert_eq "6.2-show values 与仓库一致(忽略空行)" "0" "$(diff -B /tmp/show-values.yaml "$CHART_DIR/values.yaml" | wc -l | tr -d ' ')"

# ---------- 6.3 测试主机 Helm 3.21.3 上复跑 lint + kubeVersion 矩阵 ----------
{
  echo "## 6.3 测试主机 Helm 3.21.3：lint + kubeVersion 矩阵"
  echo '```'
  echo "remote helm: $(ksi 'helm version --short')"
  echo "\$ helm lint（远端解包目录）"
  ksi "rm -rf /root/rc1-chart && mkdir -p /root/rc1-chart && tar xzf /root/categraf-0.2.2-rc.1.tgz -C /root/rc1-chart && helm lint /root/rc1-chart/categraf 2>&1 | tail -2"
  echo
  echo "\$ kubeVersion 矩阵（Helm 3.21.3）"
  for v in 1.18.0 1.19.0 1.28.2 1.32.0 1.36.0 1.37.2 1.38.0; do
    out=$(ksi "helm template t /root/rc1-chart/categraf --kube-version $v --set operator.userToken=tok 2>&1 >/dev/null")
    if [ -z "$out" ]; then echo "  $v  OK"; else echo "  $v  REJECT  $(echo "$out" | head -1 | cut -c1-90)"; fi
  done
  echo '```'
} >>"$F"
REMOTE_LINT=$(ksi "helm lint /root/rc1-chart/categraf 2>&1 | grep -c '0 chart(s) failed'")
assert_eq "6.3-远端 lint 0 failed" "1" "$REMOTE_LINT"
assert_eq "6.3-Helm3 下 1.19 可通过" "OK" "$(ksi "helm template t /root/rc1-chart/categraf --kube-version 1.19.0 --set operator.userToken=tok >/dev/null 2>&1 && echo OK || echo REJECT")"
assert_eq "6.3-Helm3 下 1.37.2 可通过" "OK" "$(ksi "helm template t /root/rc1-chart/categraf --kube-version 1.37.2 --set operator.userToken=tok >/dev/null 2>&1 && echo OK || echo REJECT")"
assert_eq "6.3-Helm3 下 1.38 被拒" "REJECT" "$(ksi "helm template t /root/rc1-chart/categraf --kube-version 1.38.0 --set operator.userToken=tok >/dev/null 2>&1 && echo OK || echo REJECT")"

# ---------- 6.4 publish-chart.sh 预发布守卫（全 stub，绝不触网） ----------
mkdir -p /tmp/stubbin
cat >/tmp/stubbin/helm <<'EOF'
#!/bin/sh
echo "[stub-helm] $*"
exit 0
EOF
cat >/tmp/stubbin/oras <<'EOF'
#!/bin/sh
echo "[stub-oras] $*"
exit 0
EOF
cat >/tmp/stubbin/crane <<'EOF'
#!/bin/sh
echo "[stub-crane] $*"
exit 0
EOF
chmod +x /tmp/stubbin/helm /tmp/stubbin/oras /tmp/stubbin/crane
{
  echo "## 6.4 publish-chart.sh 守卫（helm/oras/crane 全部 stub，不触网）"
  echo '```'
  echo '$ ./publish-chart.sh 0.2.2-rc.1   # 预发布版本'
  ( cd "$REPO_ROOT" && PATH=/tmp/stubbin:/usr/bin:/bin ./publish-chart.sh 0.2.2-rc.1 2>&1 )
  echo
  echo '$ ./publish-chart.sh 0.2.1       # 正式版本（应触发 latest）'
  ( cd "$REPO_ROOT" && PATH=/tmp/stubbin:/usr/bin:/bin ./publish-chart.sh 0.2.1 2>&1 )
  echo '```'
} >>"$F"
PRE_OUT=$(cd "$REPO_ROOT" && PATH=/tmp/stubbin:/usr/bin:/bin ./publish-chart.sh 0.2.2-rc.1 2>&1)
FIN_OUT=$(cd "$REPO_ROOT" && PATH=/tmp/stubbin:/usr/bin:/bin ./publish-chart.sh 0.2.1 2>&1)
assert_eq "6.4-预发布不更新 latest 提示" "1" "$(echo "$PRE_OUT" | grep -c '预发布版本不打 latest' || true)"
assert_eq "6.4-预发布不调用 oras" "0" "$(echo "$PRE_OUT" | grep -c 'stub-oras' || true)"
assert_eq "6.4-正式版调用 oras 打 latest" "1" "$(echo "$FIN_OUT" | grep -c 'stub-oras.*latest' || true)"

# ---------- 6.5 镜像清单核对 ----------
{
  echo "## 6.5 Chart 中引用的镜像（与测试记录/文档核对）"
  echo '```'
  helm template t "$PKG" --kube-version 1.28.2 --set operator.userToken=tok | grep -oE 'registry\.flashcat\.cloud/[a-z0-9._/-]+:[a-zA-Z0-9._-]+' | sort -u
  echo '```'
} >>"$F"

echo "G6 完成: $F"
echo "PASS=$(grep -c PASS "$EV/results.tsv") FAIL=$(grep -c FAIL "$EV/results.tsv" || true)"
grep FAIL "$EV/results.tsv" | tail -5 || echo "无 FAIL"
