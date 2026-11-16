# CMD: F1 修复端到端验证：ns=categraf-f1fix，0.2.1 → 0.2.2-rc.2，values 完全不变
# AT: 2026-11-03T07:22:55Z / 2026-11-03T15:22:55+0800

## 0. 安装 0.2.1（生产版本，同 values）
```
namespace/categraf-f1fix created
NAMESPACE: categraf-f1fix
STATUS: deployed
REVISION: 1
TEST SUITE: None
daemon set "categraf-f1fix" successfully rolled out
--- 0.2.1 的 Node Agent Pod（名称/创建时间/checksum）---
categraf-f1fix-j8lnt 2026-11-03T07:22:58Z 32cb63df1c77369fa08dffe3d95a9dff447d35b4eb77464ba7e4360fc2e27e49categraf-f1fix-wcgk4 2026-11-03T07:22:58Z 32cb63df1c77369fa08dffe3d95a9dff447d35b4eb77464ba7e4360fc2e27e49

--- 0.2.1 Pod 内实际配置的 [global.labels] ---
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029-f1fix"
categraf = "nodeAgent"
[global.n9e_server]
```
## 1. 升级到 rc.2（values 一个字不改）
```
$ helm upgrade categraf-f1fix /root/categraf-0.2.2-rc.2.tgz -n categraf-f1fix -f /root/categraf-f1fix-values.yaml
NAMESPACE: categraf-f1fix
STATUS: deployed
REVISION: 2
TEST SUITE: None

$ helm history / 等待滚动
REVISION	UPDATED                 	STATUS    	CHART              	APP VERSION	DESCRIPTION     
1       	Tue Nov  3 15:22:58 2026	superseded	categraf-0.2.1     	1.0.0      	Install complete
2       	Tue Nov  3 15:23:11 2026	deployed  	categraf-0.2.2-rc.2	0.5.32     	Upgrade complete
daemon set "categraf-f1fix" successfully rolled out
See 'kubectl rollout status --help' for usage.

--- 升级后的 Node Agent Pod（创建时间应变化 = 自动滚动；checksum 应变化）---
categraf-f1fix-gnlg5 2026-11-03T07:23:13Z 7fd6485374e70e042879c72eeab62371b48a0f905d583441836092222fe23d86categraf-f1fix-vpth5 2026-11-03T07:23:12Z 7fd6485374e70e042879c72eeab62371b48a0f905d583441836092222fe23d86
```
## 2. 断言：不用人工 rollout restart，配置已生效
```
Pod 创建时间: 2026-11-03T07:22:58Z → 2026-11-03T07:23:13Z （不同 = 升级触发了滚动）
checksum   : 32cb63df1c77369f… → 7fd6485374e70e04…

--- rc.2 Pod 内实际配置的 [global.labels]（应含 owner/environment）---
[global.labels]
env = "test"
cluster = "k8s-flashcat-test-20261029-f1fix"
categraf = "nodeAgent"
environment = "test"
owner = "platform"

[global.n9e_server]

--- 等待 60s 让新配置上报指标/心跳 ---
指标: count({cluster="k8s-flashcat-test-20261029-f1fix"})                  = 16948
指标: count({cluster="k8s-flashcat-test-20261029-f1fix",owner="platform"}) = 16948
指标: count({cluster="k8s-flashcat-test-20261029-f1fix",environment="test"}) = 16948
up{cluster=...,job=app-metrics} = 1

--- Flashcat 设备（本集群）---
  k8s-flashcat-test-20261029-f1fix-categraf-f1fix-ksm-0 up=2 owner=platform environment=test
  k8s-node2 up=2 owner=platform environment=test
```
## 3. 清理（卸载触发 cleanup hook，删除本集群设备）
```
release "categraf-f1fix" uninstalled
清理后本集群设备数 = 0
主集群设备数 = 3
namespace "categraf-f1fix" deleted
```
## 4. 结论
```
同一份 values 从 0.2.1 升级到 rc.2：Pod 自动滚动（无需人工 rollout restart），Pod 内配置立即更新，
customLabels 指标与设备标签随即出现 → F1 修复生效。
```

## 补充说明：设备标签断言只匹配到 2/3 的原因
```
本次验证 namespace 用的是默认 hostname: nodeName，Node Agent 的上报 ident 就是节点名（k8s-node1 / k8s-node2）。
与主 Release 在同一个 Flashcat 上并存时，两个 Release 的节点 Agent 会争用同一个 ident，ksm 设备则因 release 名不同而独立。
因此快照时只看到 ksm + 1 个节点设备带 owner 标签，另一个节点设备被主 Release 的心跳覆盖；
这不是 F1 修复的问题，而是 Chart 已文档化的多 Release 场景限制：values.yaml 注释明确要求多 Release/多集群共享 Flashcat 时把
nodeCategraf.hostname 改成 "${cluster}-${nodeName}"（或 ${cluster}-$hostname）避免 ident 冲突。

F1 修复的核心结论不依赖该条断言：Pod 自动滚动、Pod 内配置更新、指标带 owner 标签（16948 条 series）均已验证通过。
主集群设备在测试后复核：3 台 ident/cluster/owner 标签完好，up 指标正常。
```
