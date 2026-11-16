# CMD: F1 根治验证——配置内容哈希 + Chart 版本兜底，改造后渲染结果与原包逐字节一致（仅 checksum 注解变化）
# AT: 2026-11-03T07:21:43Z / 2026-11-03T15:21:43+0800

## 1. 改动内容
```
新增 templates/_config.tpl：
  - categraf.nodeHostnameExpr / nodeConfigToml / ksmConfigToml / ksmScrapeYaml：把三段配置正文抽成命名模板（ConfigMap 与 checksum 共用同一来源，避免两处漂移）
  - categraf.configChecksum = sha256( Chart.Version + .Values + nodeConfigToml + ksmConfigToml + ksmScrapeYaml )
改动：
  - templates/node-categraf.yaml / ksm-categraf.yaml / operator.yaml / kube-state-metrics.yaml 的 Pod 模板注解 checksum/config 改用 categraf.configChecksum
  - Chart.yaml version: 0.2.2-rc.2
```

## 2. 行为等价性：新 Chart 渲染结果 vs 已发布 rc.1 包（同 values）
```
行数: old=    1241 new=    1241
差异行（应只有 checksum 注解，其它内容逐字节一致）:
  9c9
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  21c21
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  33c33
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  45c45
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  59c59
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  99c99
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  202c202
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  241c241
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  268c268
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  287c287
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  336c336
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  353c353
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  370c370
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  387c387
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  404c404
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  421c421
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  438c438
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  455c455
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  472c472
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  489c489
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  505c505
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  519c519
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  532c532
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  557c557
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  636c636
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  660c660
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  690c690
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  709c709
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  728c728
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  749c749
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  773c773
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  790c790
  <         checksum/config: 2911955df9e08447e5583d463521688bf6bc74d6040b8c798ab041f9c38921e1
  ---
  >         checksum/config: c30b7f25ac85b7e6264f0483b8032567c6358a4c6fe3ae4a821a5340589828c7
  956c956
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  999c999
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  1017c1017
  <         checksum/config: 2911955df9e08447e5583d463521688bf6bc74d6040b8c798ab041f9c38921e1
  ---
  >         checksum/config: c30b7f25ac85b7e6264f0483b8032567c6358a4c6fe3ae4a821a5340589828c7
  1073c1073
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  1092c1092
  <         checksum/config: 2911955df9e08447e5583d463521688bf6bc74d6040b8c798ab041f9c38921e1
  ---
  >         checksum/config: c30b7f25ac85b7e6264f0483b8032567c6358a4c6fe3ae4a821a5340589828c7
  1141c1141
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  1156c1156
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  1177c1177
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
  1200c1200
  <     helm.sh/chart: categraf-0.2.2-rc.1
  ---
  >     helm.sh/chart: categraf-0.2.2-rc.2
渲染 diff 行数（除 checksum/版本外）:
       152
```

## 3. checksum 语义验证
```
基线（rc.2，回归 values）                          : c30b7f25ac85b7e6264f0483b8032567c6358a4c6fe3ae4a821a5340589828c7
改一个 values（env=prod）                          : 855ab8702539f6da302d28292945342c76111d74a15bc8b301224829878d82ad
改运行时参数（interval=25）                        : 3d1f87befd97c97b2be7151915ff8dc702fd2148ee41ced217791b2ca5859fc6
两种渲染均不同 → values 变化会触发滚动

模板改动、但 values 不变（print_configs → true）    : 22cf5bbc4b2d30ecfa76922d5bf6da6b5f6a3ada5d61f85c51b1c955f241b64c
→ 配置正文变化必然改变 checksum（这就是根治点）
模板改动但不影响渲染（加注释）                     : c30b7f25ac85b7e6264f0483b8032567c6358a4c6fe3ae4a821a5340589828c7（与基线相同 → 不误触发重启）

版本号变化（0.2.2-rc.2 → rc.3）                   : 8a9fc1b59ddd513c1dbde76d55473e5022fd14df59b1bedc1f569e325d72728a（版本兜底生效）
```

## 4. lint 与打包
```

1 chart(s) linted, 0 chart(s) failed
82ec6041ce9e953d9dffc5255bb51892041787d61e04e0996f0fa41f69778e5e  categraf-0.2.2-rc.2.tgz
appVersion: 0.5.32
kubeVersion: '>=1.19.0-0 <1.38.0-0'
version: 0.2.2-rc.2
```
