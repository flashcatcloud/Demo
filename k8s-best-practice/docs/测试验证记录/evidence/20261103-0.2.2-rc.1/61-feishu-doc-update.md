# CMD: 同步更新飞书文档《K8S 指标采集》到 0.2.2 口径
# AT: 2026-11-03T08:26:14Z / 2026-11-03T16:26:14+0800

- 文档：https://c9xudyniiq.feishu.cn/docx/Bddgd2I1Coj3AgxkDHUcndc1nRb
- 工具：lark-cli 1.0.98（`docs +fetch` / `docs +update`，user 身份）
- 版本：revision 204 → **210**

## 改动清单（6 处，全部 success、无 warnings）

| # | 位置 | 改动 |
|---|---|---|
| 1 | 1 前置条件 | Kubernetes 版本 `>= 1.21 且 < 1.32` → `>= 1.19 且 < 1.38`（注明 1.19–1.37 渲染已验证、1.28.2 实机验证） |
| 2 | 2.1 拉包解压 | 固定版本改为 **0.2.2**（当前正式版，latest 也指向它），tgz 名同步 `categraf-0.2.2.tgz` |
| 3 | 2.3 基础配置 YAML | 新增 `customLabels`、`config.interval`、`writer.batch/chanSize`、`heartbeat.interval/timeout/dialTimeout` 段 |
| 4 | 2.3 之后 | 新增「版本提示」：上述参数自 0.2.2 起提供，0.2.1 及更早会忽略 |
| 5 | 6 升级/回滚/卸载 | 新增「升级注意」：0.2.2 起 checksum 含渲染后配置，升级自动滚动；旧版本升级需 `rollout restart` |
| 6 | 6 卸载说明 | 纠正原描述：cleanup 两个开关**默认均为 true**，卸载会删除本集群设备；保留设备需显式设 false |

## 验证（fetch 复查）
```
✅ kubeVersion 1.19/1.38
✅ 拉包 0.2.2
✅ 基础配置含 customLabels / heartbeat 参数
✅ 版本提示 0.2.2 起
✅ 升级注意 checksum + rollout restart
✅ 卸载说明已纠正（pre-delete 清理 Hook）
✅ 旧描述（“默认不删设备”）已消失；旧 kubeVersion（1.21）已消失
```

## 备注
```
原文档有两处与实际 Chart 不符，本次一并修正：
1) kubeVersion 上限 1.32 会让 1.32+ 集群装不上（0.2.2 已改为 <1.38）；
2) “卸载默认不删设备”是错的——cleanup 默认 true，卸载会删设备（本轮回归 G2 实测 Hook 删除 3 台设备）。
```
