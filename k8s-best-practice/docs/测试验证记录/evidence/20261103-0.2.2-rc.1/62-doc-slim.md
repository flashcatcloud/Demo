# CMD: 飞书文档《K8S 指标采集》精简重排 + 新增「指标自动发现」章节
# AT: 2026-11-03T08:32:10Z / 2026-11-03T16:32:10+0800

- 文档：https://c9xudyniiq.feishu.cn/docx/Bddgd2I1Coj3AgxkDHUcndc1nRb
- 方式：lark-cli `docs +update --command overwrite --doc-format markdown`（user 身份）；revision 210 → **213**
- 篇幅：正文 235 行 → 217 行（**其中新增“指标自动发现”约 60 行**；原内容等价缩减约 34%）

## 1. 精简动作

| 原结构 | 现结构 | 说明 |
|---|---|---|
| 2.2 选择监控范围 + 2.3 填写必填区（重复贴 33 行 values） | 合并为 **2.2 填写 values**（14 行最小配置 + 指向 values.all.yaml） | 去掉与仓库示例重复的大段注释 |
| 3 内网部署（重复整段 helm upgrade） | **4 内网部署**：镜像表 + 覆盖 4 行 image + “重跑 2.3 命令” | 删掉重复部署命令 |
| 4 自建集群组件监控补充（4.1/4.2 长流程） | **5 其它组件指标（可选）** 3 行摘要 + **附录 A** 保留细节 | 主流程只留入口 |
| 5 验证（逐 Pod 名称清单） | 合并进 **2.3 部署并确认** 的 kubectl 命令 + 一行预期 | 消除与部署命令的重复 |
| 6 升级/回滚/卸载 + 两段版本提示分散 | **6 升级/回滚/卸载**（3 条命令 + 2 条注意）与 **7 版本说明** | 版本信息集中 |

## 2. 新增「3 指标自动发现」章节

- 机制：KSM Agent 内置 Prometheus 按 Pod SD 自动发现，只抓 `prometheus.io/scrape: "true"`，间隔 15s；
- 注解表：`scrape` / `port`（容器端口）/ `path`（默认 /metrics）/ `scheme`；
- 标签映射：Pod 标签 `app` 或 `app.kubernetes.io/name` → `service`；`team` → `team`；自动带 `namespace`/`pod`/`cluster`/`env`/`customLabels`；
- Deployment 注解示例；
- 不能改 Pod 时用 `appMetrics.extraScrapeConfigs`（原生 scrape_config 示例）；
- 验证方法（`up{job="app-metrics"}`）与 5 条常见坑（port 写错、path 不一致、改注解触发滚动、NetworkPolicy 等）；
- 与附录 A 的“控制平面自动发现”做了显式区分，避免同名混淆。

## 3. 验证
```
✅ 标题未被覆盖坏（title 保留，无重复 H1）
✅ 8 个 h2 / 8 个 h3 / 11 个代码块 / 2 个表格 / 2 个引用块
✅ 关键内容存在：指标自动发现、prometheus.io/scrape、extraScrapeConfigs、up{job="app-metrics"}、附录 A
✅ 无 Markdown 转义残留（代码块内的续行反斜杠为正常内容）
✅ 仓库同源文档已同步重写，内链校验 0 断链
```

## 4. 追加：3.3 节再精简（飞书 revision 216）
```
原 3.3「验证与常见坑」：5 条无序列表 + 1 条引用（6 项，信息平铺、有重叠）
现 3.3「验证与排错」：4 条编号步骤 + 1 条一句话区分，合并“port/path”两条为一条、
“改不了 Pod”与“NetworkPolicy”合并为一条，去掉与 3.2 重复的描述。

验证：飞书渲染为 <ol> 4 项 + <blockquote> 1 条；旧标题“验证与常见坑”已不存在。
```

## 5. 追加：澄清“内网部署”镜像占位符（飞书 revision 219）
```
问题：文档示例里写成 `mirror.example.com/...`，容易被误读成 my-values.yaml 的默认镜像地址。
事实：Chart 默认镜像就是 registry.flashcat.cloud/public/...（values.yaml 四行）；mirror.example.com 只是内网场景的占位符。

修改：
1) 第 4 节开头加提示：能直连 registry.flashcat.cloud 时本节可跳过，my-values.yaml 不用写 image；
2) 表格列改为“默认镜像（同步来源）”，明确 registry.flashcat.cloud 是来源而非覆盖值；
3) 示例占位符从 mirror.example.com 改为中文“内网仓库地址”，并明示需替换成实际地址；
4) 飞书文档同步（revision 219，已验证 mirror.example.com 不再出现）。
```

## 6. 追加：2.2 改为推荐 values.all.yaml + clusterName 说明修正（飞书 revision 222）
```
1) 2.2 起点从 values-examples/values.yaml 改为 values-examples/values.all.yaml（完整注释版），精简版作为备选；
2) clusterName 注释：原“需全局唯一”改为“必须全局唯一；每个 K8s 集群用唯一值（多集群并存也不能重复）”；
3) 说明引用同步为“以 values.all.yaml 为起点，用不到的段删掉即可”。

仓库文档与飞书文档已同步（飞书 revision 222）。
```

## 7. 追加：删除 3.3 验证与排错 + 附录 B 附完整 values.yaml（飞书 revision 226）
```
1) 删除「3.3 验证与排错」整节（用户认为啰嗦）；第 3 节保留 3.1 注解、3.2 extraScrapeConfigs；
2) 新增「附录 B 完整 values.yaml 参考」：飞书文档以附件形式挂载 values.all.yaml（9,562 bytes，文件卡片可下载），仓库文档给出文件链接；
3) 飞书 revision 222 → 226；仓库文档 218 → 215 行。

验证：飞书文档中 3.3 已不存在、附录 B 标题与附件块存在（block id doxcn9V4Avsn1xHJQsL5SI8zsLh / source token）；仓库文档内链 0 断链。
```

## 8. 追加：删除「7 版本说明」（飞书 revision 229）
```
用户判断“版本说明普通用户不关心”，删除第 7 节（0.2.2 变更说明 + 自 0.2.2 起支持的参数说明）。
仓库文档：章节编号 1-6 + 附录 A/B，无第 7 节；飞书：删 h2 + 2 条 bullet，无残留空列表。
飞书 revision 226 → 229。
```

## 9. 追加：全篇按官方文档风格重排（飞书 revision 244）
```
目标：面向普通用户，清晰/简洁/准确，排版规范化。

结构（8 个二级 + 9 个三级 + 9 张表 + 11 个代码块）：
  1 前置条件（表格）
  2 部署：2.1 拉取 Chart / 2.2 配置 values（必填表 + 可选表 + 最小示例）/ 2.3 安装与检查（检查表）
  3 应用指标自动发现：3.1 注解表 / 3.2 示例 / 3.3 extraScrapeConfigs / 3.4 验证与排查（问题-原因表）
  4 内网部署（镜像表 + 覆盖示例 + 注意）
  5 组件采集（默认值表）
  6 升级/回滚/卸载（命令 + 升级说明 + 卸载说明）
  附录 A 控制平面采集（方式对比表 + A.1/A.2 分步）
  附录 B 完整 values.yaml（附件卡片）

排版约定：术语统一（Node Agent / KSM Agent / kube-state-metrics / Operator）；
提示统一为“说明/注意”引用块；命令块标注 bash/yaml；互为引用的位置用“见附录 A/附录 B”。

仓库同源文档已同步重写（263 行，内链 0 断链）。
```

## 10. 追加：飞书文档排版格式优化（revision 261）
```
1) 说明/注意类引用块统一改为飞书高亮块（Callout）：说明=💡 light-blue、注意=⚠️ light-yellow，共 11 处；
2) 顶部新增「文档信息」表（适用版本 / 更新日期 / 适用读者）；
3) 附录 A 末尾「常用指标」由一行文字改为 5 行表格（指标 / 说明），并加三级标题；
4) 第六章与附录 A、附录 B 之间插入分隔线（共 2 条）；
5) 仓库同源文档同步：文档信息表、常用指标表、分隔线（282 行，内链 0 断链）。

校验：飞书 callout=11、table=11、hr=2，附件 values.all.yaml 仍在文末。
```

## 11. 追加：主文档去表格、内网部署并入部署章节（revision 310）
```
1) 删除全部表格（11 → 0）：前置条件、必填项、可选项、检查项、注解说明、验证排查、镜像清单、组件开关、附录对比、常用指标、文档信息，均改为列表/代码块/段落；
2) 内网部署由独立「4 内网部署」并入「2.4 内网部署（可选）」，后续章节序号前移（3 应用指标、4 组件采集、5 升级卸载）；
3) 文档信息表改为一行文字「适用版本 0.2.2 ｜ 更新日期 2026-11-03」；
4) 9 处 说明/注意 保持为高亮块（Callout），避免视觉噪音；
5) 仓库同源文档同步（含 control-plane.toml、values.all.yaml 内链）。

校验：飞书 table=0、callout=9、pre=13、附件在文末；大纲 1/2/2.1-2.4/3/3.1-3.4/4/5/附录A(A.1,A.2)/附录B。
```

## 12. 追加：主文档一致性审计与修复（revision 349）
```
发现 4 处需更新：
1) 缺「适用版本 / 更新日期」行 -> 已补；
2) 缺「常用可选项」段落 -> 已补（含 appMetrics.defaultJob.enabled）；
3) 2.2 YAML 中 appMetrics 注释仍为旧的「metrics-scrape 标签」错误口径 -> 已改为 prometheus.io/scrape 注解；
4) 附录 B 附件 values.all.yaml 为旧版（9562B，无 defaultJob） -> 已替换为最新版（9721B）。
另按用户要求：2.2 YAML 增加 defaultJob 关闭示例（注释形式），仓库文档同步。
校验：飞书 revision 349，附件 1 个/9721B，无 metrics-scrape 残留。
```
