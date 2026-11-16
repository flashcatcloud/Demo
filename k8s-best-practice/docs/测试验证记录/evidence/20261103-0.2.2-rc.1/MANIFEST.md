# 证据包 MANIFEST（categraf 0.2.2-rc.3 完整回归（rc.1 回归 + F1/F5 修复））

- 生成时间：2026-11-03T19:48:14+0800
- 被测包：`categraf-0.2.2-rc.3.tgz` SHA256 `633fd00acec54ba298702cd4f656405f7a7d1e444161f9c214b2158a68d7a00d`
- 正式版：`categraf-0.2.2.tgz` SHA256 `966ec17f1e93962ca9e9d7516c5dc84733e05b7daf4c4e721382e0b75d4683cb`，2026-11-03 发布，`latest` 指向它（见 60-publish-ga.md）
- 复跑方式：本目录 `./run-checks.sh G0|G1|G2|G3|G4|G5|G6|G7|G8a`（G2/G4/G5 会改动测试集群）
- 约定：每个证据文件头部有 `# CMD:`（原始命令）与 `# AT:`（时间戳）；正文为原始输出，未人工改写。

## 结论 → 证据索引

| 结论 | 证据文件 | 关键命令/断言 |
|---|---|---|
| 包元数据与 SHA256 | 01-static.md、70-audit.md | `helm show chart`、`shasum -a 256`、AUDIT-A1/A2 |
| 与 0.2.4 内容等价（仅元数据变化） | 01-static.md §1.3、70-audit.md | `diff -u`（归一化版本标签）、AUDIT-A6 |
| kubeVersion 边界（1.19 通过 / 1.38 拒绝） | 01-static.md §1.4、70-audit.md、50-package.md §6.3 | `helm template --kube-version`、AUDIT-A3/A4 |
| 12 条渲染期校验失败路径 | 03-negative.md | 渲染失败 + 报错文案匹配 |
| 开关矩阵（资源增减） | 04-toggles.md、05-resource-conventions.md | 渲染清单计数断言 |
| 卸载清理 Hook 删除 3 个设备、不影响他集群 | 10-lifecycle.md §1、70-audit.md | Hook Pod 日志、targets API、AUDIT-A11 |
| 0.2.1→rc.1 真实升级 / rollback / 重装 | 10-lifecycle.md §2-5 | `helm upgrade/rollback/history`、设备与 VM 快照 |
| 设备心跳、customLabels、heartbeatGid | 20-datalink.md、20-devices.json、21-up.json | targets API、`count_over_time` |
| 指标落库与关键指标族 | 20-datalink.md、21-up.json、70-audit.md | VictoriaMetrics 查询、AUDIT-A7/A8/A9 |
| 日志健康 / syslog 已知问题 | 22-logs.txt、25-upgrade-config-staleness.md | `kubectl logs` grep |
| **升级只改模板时配置不生效（F1，Chart 缺陷）** | 25-upgrade-config-staleness.md A/C 节 | ConfigMap vs Pod 内挂载对比；rollout restart 前后 VM/up 对比 |
| 配置面功能矩阵（customLabels/参数/extraScrape/inputs/组件开关/hostExec/operator） | 30-features.md | 每例 apply→断言→恢复 |
| RBAC 最小权限 | 31-rbac.md | `kubectl auth can-i` |
| 多 Release 隔离与清理范围 | 30-features.md §C9 | 命名/ClusterRole/设备隔离、卸载后设备归属 |
| 自愈（Pod 删除重建） | 40-resilience.md | 删除 Pod → 就绪 → 设备/指标恢复 |
| 包内容与仓库一致、双 Helm 版本 | 50-package.md | `diff -r`、Helm 3.21.3 lint/矩阵 |
| 发布脚本预发布守卫 | 50-package.md §6.4 | stub helm/oras 调用序列 |
| 文档一致性 | 60-doc-consistency.md | 文档声明 vs 实测对照 |
| 配置面修正轮（短窗口判定/多 Release/apiserver 诊断） | 32-features-fix.md、33-features-fix2.md | 60s 短窗口 `count_over_time`、子查询 `(up==1)[60s:15s]`、Pod 内直连 apiserver |
| 交付包溯源（文档更新后重新打包） | 55-repack.md | 两个包 diff（仅 README）、渲染 diff=0 |
| 自审复现 13 条 | 70-audit.md | 全新 shell 重跑，前缀 AUDIT- |

## 断言统计（results-final.tsv：同名用例保留最后一次结果，并对历史 FAIL 逐条分类）

```
唯一用例数=203  PASS=182  已核实/被修正覆盖=21  未解释FAIL=0
未解释的未通过用例: 无（历史 FAIL 均已分类，见 results-final.tsv）
```

## 证据文件清单（size / sha256）

```
00-baseline.md                                15886 bytes  048b6713e75f69d6
01-static.md                                   3135 bytes  5171d65972f84e7f
01b-static-rc2.md                              3166 bytes  6b5b686aa55d7a12
01c-static-rc3.md                              3166 bytes  3ad76048685f8e8d
03-negative.md                                 4060 bytes  e6795bd6d50d1eb7
03b-negative-rc2.md                            4042 bytes  a8a2d454927afd5a
03c-negative-rc3.md                            4042 bytes  9e56cd43c56368ae
04-toggles.md                                  2842 bytes  27ba5188f28a04e6
04b-toggles-rc2.md                             2842 bytes  896df88f868b57bc
04c-toggles-rc3.md                             2842 bytes  bf9f70858874370c
05-resource-conventions.md                     1732 bytes  bc62e6053924537d
05b-conventions-rc2.md                         1732 bytes  7a53027bfa352a42
05c-conventions-rc3.md                         1732 bytes  284c947df3a37384
10-lifecycle.md                               12788 bytes  06aff4ec7c02c987
20-datalink.md                                 7158 bytes  d4456c1facf25123
20-devices.json                                3714 bytes  fc812f3084866c23
21-up.json                                     2619 bytes  90747c0371cd87bb
22-logs.txt                                    2064 bytes  22956a3a3daf6bfc
25-upgrade-config-staleness.md                 5891 bytes  7f487b85737c9bdf
26-F1-rootcause.md                             2802 bytes  9f9a0c590367171f
28-F1-fix.md                                   6745 bytes  86b515761c3fe2a9
29-F1-fix-verified.md                          4200 bytes  3e06647765ab73bd
30-F5-fix.md                                   1696 bytes  e3fc5e0060393ae3
30-features.md                                 9786 bytes  ee4cb43b484865ea
31-F5-verified.md                              3841 bytes  964d7f444a137267
31-rbac.md                                      843 bytes  0109aaa2a6b9df6d
32-C7f-recheck.md                              4683 bytes  170857f7137483e2
32-features-fix.md                             2568 bytes  d405bb94c314a766
33-controlplane-apiserver.md                   1931 bytes  6ec84d6248ad16d7
33-features-fix2.md                            2731 bytes  9c88c084e5ef390e
34-path-override.md                             982 bytes  83abbbdc293741b3
35-multi-release-devices.md                   11674 bytes  aae52a513251ef2c
36-multi-release-final.md                      1710 bytes  2a880112cf39a419
40-resilience.md                               4113 bytes  02cb5868f7b45ef6
50-package.md                                  3105 bytes  aa2887d16cb2e9b0
55-repack.md                                    917 bytes  f02002599d40e015
56-repack-rc2.md                               2679 bytes  7c11745dfd5d3420
57-repack-rc3.md                               1653 bytes  7ba2d3b0c104bfda
58-publish-rc3.md                              1401 bytes  df59d498a4e1664b
59-rc3-uninstall-reinstall.md                  2563 bytes  01e4822afd06d250
60-doc-consistency.md                          4817 bytes  57d3f27b450ae262
60-publish-ga.md                               3041 bytes  efb2e7202348e659
61-feishu-doc-update.md                        1921 bytes  830189b4f6d40ebf
62-doc-slim.md                                 8701 bytes  1e6933d445a167ac
63-image-upgrade.md                            5855 bytes  425b19bdec144698
64-controlplane-a1.md                          4043 bytes  72736d62c27fed0a
65-defaultjob-and-f6.md                        1849 bytes  44b775aa33d085e2
70-audit.md                                     315 bytes  790d5b42f70fea88
FINAL_SHA                                        65 bytes  0430d0ca5bedebd2
FINDINGS.md                                   12340 bytes  9d4187af1bff7734
STATS.txt                                        97 bytes  768c943638834c3b
c7f-recheck.sh                                 2719 bytes  bada9d4621f42d28
c7f-recheck2.sh                                2562 bytes  463abe4702431a59
c7f-recheck3.sh                                2341 bytes  587b523c30ea0211
c9mini.sh                                      2282 bytes  74cfd35a549209a9
cp-a1-test.sh                                  5838 bytes  f9560ec8e8c82e86
f1fix-verify.sh                                6291 bytes  e1279b63bde6a078
f5-verify.sh                                   4349 bytes  576647cd5057e619
rc3-uninstall-reinstall.sh                     4156 bytes  5017a90ab5b029c7
results-final.tsv                              7739 bytes  9e460e0984b57a96
```

## 脚本

```
lib.sh             4788 bytes  99bed850f803c869
g0.sh              4792 bytes  bb4006157e6a866e
g1.sh             12872 bytes  824c87de7b49edce
g2.sh              7398 bytes  96032f609d9cb52c
g3.sh              7131 bytes  4bca4bcff186d45f
g4b.sh            17570 bytes  c9dd7cda355ac842
g5.sh              4681 bytes  84cc41213ece0959
g6.sh              5674 bytes  bee163279500cfd5
g7.sh              5400 bytes  7ed8009af4294ea4
g8a.sh             3596 bytes  308d15d064137762
run-checks.sh      1765 bytes  0991797a03884ce2
```
