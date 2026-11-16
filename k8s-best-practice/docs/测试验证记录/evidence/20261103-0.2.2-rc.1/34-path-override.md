# CMD: C4 深度核实：prometheus.io/path 覆盖是否真正生效（改用子查询避免 5 分钟 lookback 误判）
# AT: 2026-11-03T06:42:51Z / 2026-11-03T14:42:51+0800

## 改前
```
pod 注解: {"prometheus.io/path":"/metrics","prometheus.io/port":"8080","prometheus.io/scheme":"http","prometheus.io/scrape":"true"}
up{job=app-metrics} 值集合 = [1]
90s 内 up==1 的样本数 = 1
```
## 改坏 path -> /metrics-broken

```
pod 注解: {"prometheus.io/path":"/metrics-broken","prometheus.io/port":"8080","prometheus.io/scheme":"http","prometheus.io/scrape":"true"}
up 值集合 = [0]
90s 内 up==1 的样本数 = 1
```
## 恢复 path -> /metrics

```
up 值集合 = [1]
90s 内 up==1 的样本数 = 1
```

## 结论
```
改坏 prometheus.io/path 后 up 变成 0（抓取失败），恢复后回到 1 → annotation 路径覆盖生效。
上一轮判 FAIL 是滚动期间同时存在新旧 target、单取 .data.result[0] 造成的取数错误，不是 Chart 缺陷。
```
