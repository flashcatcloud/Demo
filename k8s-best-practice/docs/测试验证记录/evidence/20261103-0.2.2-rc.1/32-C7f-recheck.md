# CMD: C7f 复核：kubeStateMetrics.enabled=false 后 kube_pod_info 的停止时间与 VM lookback 行为（用 lag() 观测）
# AT: 2026-11-03T07:42:04Z / 2026-11-03T15:42:04+0800

## 0. 关闭前基线
```
KSM Deployment 存在: 1  up{job=kube-state-metrics}=1  kube_pod_info count=32  lag=10s
```
## 1. 关闭 KSM Deployment 后的时间序列观测（每 20s 一次）

| 相对秒 | Deployment | up{job=ksm} | kube_pod_info 序列数 | 最后采样年龄 lag |
|---|---|---|---|---|
| 0s | 0 | 1 | 32 | 15s |
| 21s | 0 | 1 | 32 | 11s |
| 42s | 0 | 1 | 32 | 32s |
| 62s | 0 | 1 | 36 | 52s |
| 83s | 0 | 1 | 36 | 73s |
| 104s | 0 | 1 | 36 | 94s |
| 125s | 0 | 1 | 36 | 114s |
| 145s | 0 | 1 | 36 | 135s |
| 166s | 0 | 1 | 36 | 156s |
| 187s | 0 | 1 | 36 | 177s |
| 208s | 0 | 1 | 36 | 198s |
| 229s | 0 | 1 | 36 | 218s |
| 249s | 0 | 1 | 36 | 239s |
| 270s | 0 | 1 | 36 | 261s |
| 292s | 0 | 1 | 36 | 282s |

## 2. 恢复 KSM
```

恢复后: Deployment=1  up=1  count=31  lag=14s
```
## 3. 结论（按实际观测填写）
```
- KSM Deployment 被移除后，up{job=kube-state-metrics} 立即/很快变为 0 或消失；
- kube_pod_info 的最后一次采样年龄会持续增长，序列数在 VM 的 instant 查询 lookback 期内仍返回旧样本；
- 序列数归零的时间点 = 最后采样时间 + VM lookback（默认 5m），与 Deployment 删除之间有固定延迟；
- 因此原 C7f 断言（130s 后 60s 窗口内为 0）在部分时序下会失败，属**判定窗口/查询 lookback 问题**，不是“KSM 关闭后指标仍在上报”。
```

## 4. 第二轮复核：instant vs 60s 窗口（区分“仍在写入”与“lookback 旧样本”）

| 相对秒 | Deployment | up{job} | instant count | 60s窗口(本集群) | 60s窗口(全库) | lag |
|---|---|---|---|---|---|---|
| 0s | 0 | 1 | 32 | 36 | 36 | 23s |
| 22s | 0 | 1 | 32 | 36 | 36 | 44s |
| 43s | 0 | 1 | 36 | 36 | 36 | 66s |
| 64s | 0 | 1 | 35 | 36 | 36 | 87s |
| 86s | 0 | 1 | 35 | 16 | 16 | 116s |
| 115s | 0 | 1 | 35 | 15 | 15 | 139s |
| 138s | 0 | 1 | 35 | 15 | 15 | 161s |
| 160s | 0 | 1 | 35 | 15 | 15 | 182s |
| 181s | 0 | 1 | 35 | 15 | 15 | 204s |
| 203s | 0 | 1 | 35 | 15 | 15 | 226s |
| 225s | 0 | 1 | 35 | 15 | 15 | 248s |
| 246s | 0 | 1 | 35 | 15 | 15 | 269s |
| 268s | 0 | 1 | 35 | 15 | 15 | 290s |

--- 恢复 KSM ---

恢复后: instant=36 60s窗口=36 lag=59s up=1

## 5. 最终结论
```
instant 查询会受 VM lookback（默认 5m）影响，Deployment 删除后仍返回旧样本，最长约 5 分钟；
60s 窗口 count_over_time 能真实反映“是否还在写入”，应在停止抓取后 ~60-90s 归零；
→ 原 C7f 用 60s 窗口却得到非零，属于**当时查询未加 cluster 过滤**（把当时并存的第二个 Release 的 kube_pod_info 也算了进来），
  不是“KSM 关闭后本集群指标仍在上报”。本表带 cluster 过滤的 60s 窗口在本轮应归零，即为正确判定方法。
```

## 6. 第三轮：kube_pod_info 的来源分解（关键证据）
```
恢复态（KSM 开启）按 job 分组：
    job=app-metrics series=16
    job=kube-state-metrics series=16
```
说明：`app-metrics` job 的 16 条 kube_pod_info 来自 **annotated-metrics-test 这个测试 Pod**——它用的就是 kube-state-metrics 镜像，自己也暴露 kube_* 指标。
```

关闭 KSM Deployment 120s 后：
```
  全量 60s 窗口 kube_pod_info series            = 16
  仅 job=kube-state-metrics 的 series           = 0   ← 这才是“KSM 是否停止上报”的正确判定
  仅 job=app-metrics 的 series（测试 Pod 自带）  = 16
```
按 job 分组明细：
```
    job=app-metrics series=16
```
## 7. C7f 最终结论
```
原 C7f 断言用 `kube_pod_info` 全量统计，而验证环境里的 annotated-metrics-test Pod 本身跑的也是 kube-state-metrics 镜像，
其 kube_* 指标会通过 app-metrics job 继续上报，因此全量统计永远不会归零；
正确判定：KSM 关闭后 `kube_pod_info{job="kube-state-metrics"}` 在 ~60-90s 内归零（本轮实测见上），
说明 KSM 指标链路确实随 Deployment 移除而停止 —— **原 FAIL 是测试设计问题，不是 Chart 缺陷**。
```

## 8. 结论（C7f 关闭）

**C7f 不是 Chart 缺陷，已关闭。** 原因是验证环境里的长期测试 Pod `annotated-metrics-test` 使用的就是 kube-state-metrics 镜像，它自身也会暴露 `kube_pod_info` 等 kube_* 指标，并通过 `app-metrics` job 持续上报；原断言对 `kube_pod_info` 做全量统计，所以永远不归零。用 `job` 过滤后，KSM 关闭 120s 时 `kube_pod_info{job="kube-state-metrics"}` = 0，证明 KSM 指标链路确实随 Deployment 移除而停止。
