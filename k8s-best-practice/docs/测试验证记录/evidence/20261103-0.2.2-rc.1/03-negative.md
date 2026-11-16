# CMD: G1 负向用例：每个用例必须渲染失败且报错文案匹配
# AT: 2026-11-03T05:09:06Z / 2026-11-03T13:09:06+0800

# 负向用例原始输出

### interval=0
```
期望错误含: categraf.config.interval must be greater than 0
Error: execution error at (categraf/templates/node-categraf.yaml:2:4): categraf.config.interval must be greater than 0

Use --debug flag to render out invalid YAML
```
### interval=-1
```
期望错误含: categraf.config.interval must be greater than 0
Error: execution error at (categraf/templates/node-categraf.yaml:2:4): categraf.config.interval must be greater than 0

Use --debug flag to render out invalid YAML
```
### batch=-1
```
期望错误含: categraf.writer.batch must be greater than or equal to 0
Error: execution error at (categraf/templates/node-categraf.yaml:2:4): categraf.writer.batch must be greater than or equal to 0

Use --debug flag to render out invalid YAML
```
### chanSize=0
```
期望错误含: categraf.writer.chanSize must be greater than 0
Error: execution error at (categraf/templates/node-categraf.yaml:2:4): categraf.writer.chanSize must be greater than 0

Use --debug flag to render out invalid YAML
```
### heartbeat.interval=0
```
期望错误含: categraf.heartbeat.interval must be greater than 0
Error: execution error at (categraf/templates/node-categraf.yaml:2:4): categraf.heartbeat.interval must be greater than 0

Use --debug flag to render out invalid YAML
```
### heartbeat.timeout=0
```
期望错误含: categraf.heartbeat.timeout must be greater than 0
Error: execution error at (categraf/templates/node-categraf.yaml:2:4): categraf.heartbeat.timeout must be greater than 0

Use --debug flag to render out invalid YAML
```
### heartbeat.dialTimeout=0
```
期望错误含: categraf.heartbeat.dialTimeout must be greater than 0
Error: execution error at (categraf/templates/node-categraf.yaml:2:4): categraf.heartbeat.dialTimeout must be greater than 0

Use --debug flag to render out invalid YAML
```
### customLabels 覆盖 cluster
```
期望错误含: cannot override reserved label
Error: execution error at (categraf/templates/node-categraf.yaml:37:8): categraf.customLabels cannot override reserved label "cluster"

Use --debug flag to render out invalid YAML
```
### customLabels 覆盖 env
```
期望错误含: cannot override reserved label
Error: execution error at (categraf/templates/node-categraf.yaml:37:8): categraf.customLabels cannot override reserved label "env"

Use --debug flag to render out invalid YAML
```
### customLabels 覆盖 categraf
```
期望错误含: cannot override reserved label
Error: execution error at (categraf/templates/node-categraf.yaml:37:8): categraf.customLabels cannot override reserved label "categraf"

Use --debug flag to render out invalid YAML
```
### customLabels 非法键 foo-bar
```
期望错误含: is not a valid Prometheus label name
Error: execution error at (categraf/templates/node-categraf.yaml:37:8): categraf.customLabels key "foo-bar" is not a valid Prometheus label name

Use --debug flag to render out invalid YAML
```
### customLabels 值为 map
```
期望错误含: must be a string, number or boolean
Error: execution error at (categraf/templates/node-categraf.yaml:37:8): categraf.customLabels["region"] must be a string, number or boolean

Use --debug flag to render out invalid YAML
```
### operator 无 userToken
```
期望错误含: operator.userToken 必填
Error: execution error at (categraf/templates/operator.yaml:2:4): operator.enabled=true 时 operator.userToken 必填；不需要清理请设置 operator.enabled=false

Use --debug flag to render out invalid YAML
```
### extraScrapeConfigs 非 list
```
期望错误含: appMetrics.extraScrapeConfigs must be a list
Error: execution error at (categraf/templates/ksm-categraf.yaml:68:10): appMetrics.extraScrapeConfigs must be a list

Use --debug flag to render out invalid YAML
```
### 正向 batch=0（允许，回落 Node=2000 / KSM=1000）
```
    batch = 1000
    chan_size = 1000000
    batch = 2000
    chan_size = 1000000
```
