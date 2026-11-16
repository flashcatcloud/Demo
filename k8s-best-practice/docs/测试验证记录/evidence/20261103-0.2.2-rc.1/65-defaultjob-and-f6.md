# CMD: 新增 appMetrics.defaultJob.enabled 开关 + 修复 extraScrapeConfigs 缩进（F6）+ 真机验证 AutoMQ 自定义注解
# AT: 2026-11-03T11:43:07Z / 2026-11-03T19:43:07+0800

## 1. 变更
```
1) 新增开关 appMetrics.defaultJob.enabled（默认 true）：false 时不再渲染内置 prometheus.io/* 的 app-metrics job，只保留 extraScrapeConfigs；
2) 修复 F6：extraScrapeConfigs 渲染缩进由 nindent 6 改为 nindent 2（之前生成的 YAML 非法，KSM Agent 报 "field job_name not found in type relabel.plain" 并加载配置失败，集群级采集全部中断）；
3) values.yaml / values-examples 同步注释。
```

## 2. 渲染验证
```
默认（app-metrics job 存在）: helm template ... | grep -c "job_name: 'app-metrics'" -> 1
defaultJob.enabled=false: app-metrics 消失，extraScrapeConfigs 的 automq job 保留（缩进与其他 job 一致）
appMetrics.enabled=false: 两者都不渲染
helm lint: 1 chart(s) linted, 0 chart(s) failed
```

## 3. 真机验证（测试集群，mock AutoMQ Pod）
```
Pod 注解：prometheus.io/automq-scrape=true / automq-port=8080 / automq-path=/metrics（镜像 kube-state-metrics，暴露 /metrics）
values：appMetrics.defaultJob.enabled=false + extraScrapeConfigs 的 automq job（注解映射）
结果：
  up{job="automq"} = 1，service=automq-mock
  automq 指标数 = 5
  app-metrics 近 1 分钟样本 = 0（默认 job 已关闭）
  KSM Agent 日志无配置加载错误
```

## 4. 还原
```
  mock Deployment 已删除；helm 回到 baseline values（REVISION 10），app-metrics job 恢复（1 个）
```

## 5. 发布
```
  0.2.2 覆盖重推：SHA256 cbc1c7455f39facb1bfb2d9bed3d9c5d05423b2d8f28cbe07f49dd8cc0ffe461
  OCI Digest sha256:1aaa78360b1196a41da89b1c1d3148f4883e93ada98aa54d90cb54f1d7cd8400；latest 同步
  拉回包 SHA 与本地一致
```
