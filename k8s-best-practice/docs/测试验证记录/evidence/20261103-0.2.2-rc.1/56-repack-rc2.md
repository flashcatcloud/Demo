# CMD: rc.1 → rc.2 交付包溯源（F1 修复），证明运行时行为差异仅限“是否滚动”
# AT: 2026-11-03T07:22:21Z / 2026-11-03T15:22:21+0800

## 1. 包 SHA256
```
rc.1（完整回归执行时的包）: abad2980c6f01a75e2533c88c5c7baa1a460c050820de8840a78556c27ddd725
rc.2（F1 修复后交付包）  : 82ec6041ce9e953d9dffc5255bb51892041787d61e04e0996f0fa41f69778e5e
大小: 17778 bytes
```
## 2. 包内文件差异
```
  Files /tmp/rc2-old/categraf/Chart.yaml and /tmp/rc2-new/categraf/Chart.yaml differ
  Only in /tmp/rc2-new/categraf/templates: _config.tpl
  Files /tmp/rc2-old/categraf/templates/ksm-categraf.yaml and /tmp/rc2-new/categraf/templates/ksm-categraf.yaml differ
  Files /tmp/rc2-old/categraf/templates/node-categraf.yaml and /tmp/rc2-new/categraf/templates/node-categraf.yaml differ
  Files /tmp/rc2-old/categraf/templates/operator.yaml and /tmp/rc2-new/categraf/templates/operator.yaml differ
```
## 3. 渲染等价性（同 values，归一化版本标签与 checksum 后应 0 差异）
```
  归一化 diff 行数:        0
  checksum 注解对比:
    rc.1:         checksum/config: 2911955df9e08447e5583d463521688bf6bc74d6040b8c798ab041f9c38921e1
    rc.2:         checksum/config: c30b7f25ac85b7e6264f0483b8032567c6358a4c6fe3ae4a821a5340589828c7
```
## 4. lint
```

1 chart(s) linted, 0 chart(s) failed
```
## 5. 结论
```
rc.2 相对 rc.1 只改了模板（新增 _config.tpl、4 个 workload 的 checksum 注解、版本号），
渲染出的资源除 checksum/版本标签外逐字节一致 → 运行时行为不变，只修复“配置变了却不滚动”的触发逻辑。
```

## 6. 追加：README 升级说明更新后重新打包
```
更新 Chart README 的 F1 升级说明后重新打包 rc.2。
打包前 SHA: 82ec6041ce9e953d9dffc5255bb51892041787d61e04e0996f0fa41f69778e5e
打包后 SHA: 7b5fb0601853fda478e0fe42ad2ec34405c8bb430e14318d1306c9947cbeeac0
差异（应只有 README.md）:
  Files /tmp/rc2-new/categraf/Chart.yaml and assets/categraf-helm/categraf/Chart.yaml differ
  Files /tmp/rc2-new/categraf/README.md and assets/categraf-helm/categraf/README.md differ
模板渲染等价性：
  归一化 diff 行数:        0
```

## 7. 主测试集群升级到 rc.2（最终交付包）
```
NAMESPACE: categraf
STATUS: deployed
REVISION: 36
TEST SUITE: None
daemon set "categraf" successfully rolled out
--- 设备/指标复核 ---
设备 target_up=2: 3/3
up 异常: 0
owner 标签 series: 34775
NAME    	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART              	APP VERSION
categraf	categraf 	36      	2026-11-03 15:26:32.309553256 +0800 CST	deployed	categraf-0.2.2-rc.2	0.5.32     
```
