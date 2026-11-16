#!/usr/bin/env bash
# G8b 汇总：results.tsv 去重统计 + 证据文件清单（sha256）+ MANIFEST 骨架
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
M="$EV/MANIFEST.md"

{
  echo "# 证据包 MANIFEST（categraf 0.2.2-rc.3 完整回归（rc.1 回归 + F1/F5 修复））"
  echo
  echo "- 生成时间：$(date +%FT%T%z)"
  echo "- 被测包：\`categraf-0.2.2-rc.3.tgz\` SHA256 \`$(shasum -a 256 "$REPO_ROOT/categraf-0.2.2-rc.3.tgz" | awk '{print $1}')\`"
  echo "- 正式版：\`categraf-0.2.2.tgz\` SHA256 \`966ec17f1e93962ca9e9d7516c5dc84733e05b7daf4c4e721382e0b75d4683cb\`，2026-11-03 发布，\`latest\` 指向它（见 60-publish-ga.md）"
  echo "- 复跑方式：本目录 \`./run-checks.sh G0|G1|G2|G3|G4|G5|G6|G7|G8a\`（G2/G4/G5 会改动测试集群）"
  echo "- 约定：每个证据文件头部有 \`# CMD:\`（原始命令）与 \`# AT:\`（时间戳）；正文为原始输出，未人工改写。"
  echo
  echo "## 结论 → 证据索引"
  echo
  echo '| 结论 | 证据文件 | 关键命令/断言 |'
  echo '|---|---|---|'
  echo '| 包元数据与 SHA256 | 01-static.md、70-audit.md | `helm show chart`、`shasum -a 256`、AUDIT-A1/A2 |'
  echo '| 与 0.2.4 内容等价（仅元数据变化） | 01-static.md §1.3、70-audit.md | `diff -u`（归一化版本标签）、AUDIT-A6 |'
  echo '| kubeVersion 边界（1.19 通过 / 1.38 拒绝） | 01-static.md §1.4、70-audit.md、50-package.md §6.3 | `helm template --kube-version`、AUDIT-A3/A4 |'
  echo '| 12 条渲染期校验失败路径 | 03-negative.md | 渲染失败 + 报错文案匹配 |'
  echo '| 开关矩阵（资源增减） | 04-toggles.md、05-resource-conventions.md | 渲染清单计数断言 |'
  echo '| 卸载清理 Hook 删除 3 个设备、不影响他集群 | 10-lifecycle.md §1、70-audit.md | Hook Pod 日志、targets API、AUDIT-A11 |'
  echo '| 0.2.1→rc.1 真实升级 / rollback / 重装 | 10-lifecycle.md §2-5 | `helm upgrade/rollback/history`、设备与 VM 快照 |'
  echo '| 设备心跳、customLabels、heartbeatGid | 20-datalink.md、20-devices.json、21-up.json | targets API、`count_over_time` |'
  echo '| 指标落库与关键指标族 | 20-datalink.md、21-up.json、70-audit.md | VictoriaMetrics 查询、AUDIT-A7/A8/A9 |'
  echo '| 日志健康 / syslog 已知问题 | 22-logs.txt、25-upgrade-config-staleness.md | `kubectl logs` grep |'
  echo '| **升级只改模板时配置不生效（F1，Chart 缺陷）** | 25-upgrade-config-staleness.md A/C 节 | ConfigMap vs Pod 内挂载对比；rollout restart 前后 VM/up 对比 |'
  echo '| 配置面功能矩阵（customLabels/参数/extraScrape/inputs/组件开关/hostExec/operator） | 30-features.md | 每例 apply→断言→恢复 |'
  echo '| RBAC 最小权限 | 31-rbac.md | `kubectl auth can-i` |'
  echo '| 多 Release 隔离与清理范围 | 30-features.md §C9 | 命名/ClusterRole/设备隔离、卸载后设备归属 |'
  echo '| 自愈（Pod 删除重建） | 40-resilience.md | 删除 Pod → 就绪 → 设备/指标恢复 |'
  echo '| 包内容与仓库一致、双 Helm 版本 | 50-package.md | `diff -r`、Helm 3.21.3 lint/矩阵 |'
  echo '| 发布脚本预发布守卫 | 50-package.md §6.4 | stub helm/oras 调用序列 |'
  echo '| 文档一致性 | 60-doc-consistency.md | 文档声明 vs 实测对照 |'
  echo '| 配置面修正轮（短窗口判定/多 Release/apiserver 诊断） | 32-features-fix.md、33-features-fix2.md | 60s 短窗口 `count_over_time`、子查询 `(up==1)[60s:15s]`、Pod 内直连 apiserver |'
  echo '| 交付包溯源（文档更新后重新打包） | 55-repack.md | 两个包 diff（仅 README）、渲染 diff=0 |'
  echo '| 自审复现 13 条 | 70-audit.md | 全新 shell 重跑，前缀 AUDIT- |'
  echo
  echo "## 断言统计（results-final.tsv：同名用例保留最后一次结果，并对历史 FAIL 逐条分类）"
  echo
  echo '```'
  python3 - <<'PY'
import collections, os
p='results-final.tsv' if os.path.exists('results-final.tsv') else 'results.tsv'
last={}
order=[]
for line in open(p, encoding='utf-8'):
    parts=line.rstrip('\n').split('\t')
    if parts and parts[0]=='状态': continue
    if len(parts)<2: continue
    st,name=parts[0],parts[1]
    if name not in last: order.append(name)
    last[name]=st
c=collections.Counter(last.values())
print(f"唯一用例数={len(last)}  PASS={c.get('PASS',0)}  已核实/被修正覆盖={c.get('SUPERSEDED/EXPLAINED',0)}  未解释FAIL={c.get('UNEXPLAINED-FAIL',0)+c.get('FAIL',0)}")
fails=[n for n in order if last[n] not in ('PASS','SUPERSEDED/EXPLAINED')]
if fails:
    print("未解释的未通过用例:")
    for n in fails: print("  -",n)
else:
    print("未解释的未通过用例: 无（历史 FAIL 均已分类，见 results-final.tsv）")
PY
  echo '```'
  echo
  echo "## 证据文件清单（size / sha256）"
  echo
  echo '```'
  for f in $(ls -1 | grep -vE '^(lib\.sh|g[0-9].*\.sh|run-checks\.sh|MANIFEST\.md|results\.tsv|_render-.*)$' | sort); do
    [ -f "$f" ] && printf '%-42s %8s bytes  %s\n' "$f" "$(wc -c <"$f" | tr -d ' ')" "$(shasum -a 256 "$f" | cut -c1-16)"
  done
  echo '```'
  echo
  echo "## 脚本"
  echo
  echo '```'
  for f in lib.sh g0.sh g1.sh g2.sh g3.sh g4b.sh g5.sh g6.sh g7.sh g8a.sh run-checks.sh; do
    [ -f "$f" ] && printf '%-16s %6s bytes  %s\n' "$f" "$(wc -c <"$f" | tr -d ' ')" "$(shasum -a 256 "$f" | cut -c1-16)"
  done
  echo '```'
} >"$M"

echo "MANIFEST 生成: $M"
head -20 "$M"
