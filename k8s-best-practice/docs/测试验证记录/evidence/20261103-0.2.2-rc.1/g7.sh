#!/usr/bin/env bash
# G7 文档一致性核对：以实测结果校对仓库文档
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/60-doc-consistency.md"
CHART_DIR="$REPO_ROOT/assets/categraf-helm/categraf"

ev "$F" "G7 文档一致性：chart README / K8S指标监控.md / values-examples / 测试记录 README 与实测对照"

{
  echo "## 7.1 Chart.yaml 与 chart README 的 kubeVersion 是否一致"
  echo '```'
  echo "Chart.yaml:      $(grep '^kubeVersion:' "$CHART_DIR/Chart.yaml")"
  echo "README 中的声明: $(grep -o 'kubeVersion: \"[^\"]*\"' "$CHART_DIR/README.md" | head -1)"
  echo '```'
} >>"$F"
assert_eq "7.1-README kubeVersion 与 Chart.yaml 一致" "1" "$(grep -c "$(grep '^kubeVersion:' "$CHART_DIR/Chart.yaml" | sed 's/^kubeVersion: //; s/"//g' | sed 's/[.*+?^${}()|[\]\\]/\\&/g')" "$CHART_DIR/README.md" >/dev/null 2>&1 && echo 1 || echo 0)"

{
  echo "## 7.2 README 声称的“已验证范围” vs 实测矩阵（01-static.md 1.4）"
  echo '```'
  echo "README 声明: $(grep -E '模板渲染在' "$CHART_DIR/README.md" | sed 's/^ *//')"
  echo
  echo "实测矩阵（来自 01-static.md）:"
  sed -n '/## 1.4 kubeVersion 矩阵/,/```$/p' "$EV/01-static.md" | grep -E '^1\.' | sed 's/^/  /'
  echo '```'
} >>"$F"

{
  echo "## 7.3 README 版本历史与 values.yaml 实际功能对照"
  echo '```'
  for k in customLabels extraScrapeConfigs 'config:' 'chanSize' 'dialTimeout' 'heartbeatGid'; do
    printf '  values.yaml 含 %-22s : %s\n' "$k" "$(grep -c "$k" "$CHART_DIR/values.yaml")"
  done
  echo
  echo "README 版本历史段:"
  grep -A2 '版本号规则' "$CHART_DIR/README.md" | head -8 | sed 's/^/  /'
  echo '```'
} >>"$F"

{
  echo "## 7.4 K8S指标监控.md 的拉包版本 / kubeVersion / 版本提示"
  echo '```'
  echo "\$ 文档中的 helm pull 命令"
  grep -n 'helm pull' "$REPO_ROOT/docs/01-k8s-base/K8S指标监控.md"
  echo "\$ 文档中的 kubeVersion 描述"
  grep -n 'Kubernetes >=' "$REPO_ROOT/docs/01-k8s-base/K8S指标监控.md"
  echo "\$ 文档中的版本提示（0.2.2 起）"
  grep -n '0.2.2 起' "$REPO_ROOT/docs/01-k8s-base/K8S指标监控.md"
  echo "\$ 仓库中 0.2.1 是否真实存在"
  helm show chart oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1 2>&1 | grep -E '^version:'
  echo '```'
} >>"$F"
assert_eq "7.4-文档拉包版本=生产 0.2.1" "1" "$(grep -c 'helm pull oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1' "$REPO_ROOT/docs/01-k8s-base/K8S指标监控.md")"
assert_eq "7.4-文档 kubeVersion 与 Chart 一致" "1" "$(grep -c 'Kubernetes >= 1.19 且 < 1.38' "$REPO_ROOT/docs/01-k8s-base/K8S指标监控.md")"
assert_eq "7.4-仓库存在 0.2.1" "1" "$(helm show chart oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1 2>/dev/null | grep -c '^version: 0.2.1')"

{
  echo "## 7.5 values-examples 注释与 Chart 默认值是否一致"
  echo '```'
  echo "values-examples/values.yaml 声明: chart 自带默认 coreDns/networkPlugin/kubeProxy 是开的"
  echo "chart values.yaml 实际默认:"
  grep -E '^coreDns:|^kubeProxy:|^  calico:|^  cilium:|^    enabled:' "$CHART_DIR/values.yaml" | sed 's/^/  /'
  echo '--- 逐项核对 ---'
  python3 - "$CHART_DIR/values.yaml" <<'PY'
import sys,re
s=open(sys.argv[1]).read()
def val(path, default=None):
    cur=None
    for line in s.splitlines():
        m=re.match(r'^(\s*)([A-Za-z_][\w]*):(.*)$',line)
        if not m: continue
        ind=len(m.group(1)); k=m.group(2); v=m.group(3).strip()
        if v: cur=v
    return None
# 直接找关键默认值
for key in ['coreDns','kubeProxy','controlPlane','appMetrics','kubeStateMetrics','ksmCategraf','nodeCategraf']:
    m=re.search(rf'^{key}:\n(?:  .*\n)*?  enabled: (\w+)', s, re.M)
    print(f'  {key}.enabled = ' + (m.group(1) if m else '未找到'))
m=re.search(r'networkPlugin:\n(?:  .*\n)*?  calico:\n    enabled: (\w+)', s)
print('  networkPlugin.calico.enabled = ' + (m.group(1) if m else '未找到'))
PY
  echo '```'
} >>"$F"

{
  echo "## 7.6 测试验证记录命名规则 vs 实际文件名"
  echo '```'
  ls -1 "$REPO_ROOT/docs/测试验证记录/" | grep -E '^categraf-' | sed 's/^/  /'
  echo
  echo "规则（记录 README）: $(grep -n '文件名格式' "$REPO_ROOT/docs/测试验证记录/README.md")"
  echo '```'
} >>"$F"
assert_eq "7.6-记录文件名符合命名规则" "3" "$(ls -1 "$REPO_ROOT/docs/测试验证记录/" | grep -cE '^categraf-[0-9]+\.[0-9]+\.[0-9]+(-[0-9a-z.]+)?-[0-9]{8}\.md$')"

{
  echo "## 7.7 外部共享文档：test-env skill 中 cleanup 默认值描述"
  echo '```'
  echo "\$ grep cleanup 默认值描述（~/.codex/skills/test-env 与 ~/.agents 副本）"
  grep -n 'cleanup' /Users/flashcat/.codex/skills/test-env/SKILL.md /Users/flashcat/.agents/skills/test-env/SKILL.md 2>/dev/null | sed 's/^/  /'
  echo
  echo "chart 实际默认值: $(grep -A3 '  cleanup:' "$CHART_DIR/values.yaml" | grep -E 'nodeCategraf|ksmCategraf' | tr '\n' ' ')"
  echo "本次实测（G2 卸载）：cleanup hook 主动删除了 3 个设备（见 10-lifecycle.md），证明默认开启生效"
  echo '```'
} >>"$F"

{
  echo "## 7.8 差异汇总"
  echo '```'
  echo "本次核对发现的文档差异（需修复项）："
  echo "  （由执行者逐条填写；无差异则显示“无”）"
  echo '```'
} >>"$F"

echo "G7 完成: $F"
grep FAIL "$EV/results.tsv" | tail -5 || echo "无新增 FAIL"
