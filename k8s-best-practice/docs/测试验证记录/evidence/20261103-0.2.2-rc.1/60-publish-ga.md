# CMD: 发布正式版 0.2.2 到 OCI 仓库（更新 latest）
# AT: 2026-11-03T08:19:40Z / 2026-11-03T16:19:40+0800

## 1. 推前状态
```
latest = 0.2.1（生产版本）
```
## 2. 正式版包
```
categraf-0.2.2.tgz SHA256 = 966ec17f1e93962ca9e9d7516c5dc84733e05b7daf4c4e721382e0b75d4683cb
version=0.2.2  appVersion=0.5.32  kubeVersion='>=1.19.0-0 <1.38.0-0'
与 rc.3 渲染等价性（归一化版本/checksum）：回归 values diff=0，默认 values diff=0
```
## 3. 发布输出
```
Pushed: registry.flashcat.cloud/public/charts/categraf:0.2.2
Digest: sha256:c2f94715dd2c799bcacb8af32297b84b1c76f062e330e6534e32ef1ea8de7174
Digest: sha256:c2f94715dd2c799bcacb8af32297b84b1c76f062e330e6534e32ef1ea8de7174
==> 打 latest 标签（oras）
Copied [registry] registry.flashcat.cloud/public/charts/categraf:0.2.2 => [registry] registry.flashcat.cloud/public/charts/categraf:latest
Digest: sha256:c2f94715dd2c799bcacb8af32297b84b1c76f062e330e6534e32ef1ea8de7174
推送完成: oci://registry.flashcat.cloud/public/charts/categraf:0.2.2
```
## 4. 推后校验
```
远端 0.2.2 拉回包 SHA256 = 966ec17f1e93962ca9e9d7516c5dc84733e05b7daf4c4e721382e0b75d4683cb  (与本地一致)
远端 latest 拉回包 SHA256 = 966ec17f1e93962ca9e9d7516c5dc84733e05b7daf4c4e721382e0b75d4683cb  (与本地一致)
latest 当前版本 = 0.2.2（Asia/Shanghai 2026-11-03T16:19:40）
```
## 5. 结论
```
0.2.2 正式版已发布并更新 latest（从 0.2.1 → 0.2.2）；
0.2.1 与 0.2.2-rc.3 仍保留，可随时回退（helm pull --version 0.2.1；latest 回滚用 oras copy 0.2.1 → latest）。
```

## 6. 真机验证：主测试集群升级到正式版 0.2.2
```
$ helm upgrade categraf /root/categraf-0.2.2.tgz（同一份 values）
STATUS: deployed
REVISION: 2
TEST SUITE: None
daemon set "categraf" successfully rolled out

## 6. 真机验证：主测试集群升级到正式版 0.2.2
```
$ helm upgrade categraf /root/categraf-0.2.2.tgz -n categraf -f /root/categraf-024-regression-values.yaml
categraf	categraf 	2       	2026-11-03 16:19:50.15979201 +0800 CST	deployed	categraf-0.2.2	0.5.32     
Node Agent Pod（新版已滚动）:
NAME             CREATED                STATUS
categraf-lwxjf   2026-11-03T08:19:51Z   Running
categraf-ptr79   2026-11-03T08:19:52Z   Running
设备 target_up=2: 3/3
up 异常条数: 0
series: 15240
customLabels: count({owner="platform"}) = 15240
```
结论：正式版 0.2.2 在测试集群升级成功，版本变化触发 Pod 自动滚动（F1 修复生效），设备与指标正常。

## 7. 后续覆盖重推说明（2026-11-03 晚）

因镜像升级到 categraf_ent v0.5.45 / servicemap-v0.5.45，0.2.2 于同日**覆盖重推**（版本号不变）：
- 新包 SHA256 `7b1b18c01aad2d9a3da29816730ea122dba120399895335d68ddbe5620bcec0f`，OCI Digest `sha256:93f5f5b6f010f915eb2af0ac5717a98dc9e0e49c4f75fef17dc01bd233f1573e`，latest 已指向新包；
- 旧包 SHA256 `966ec17f…68d75d` 仅作历史记录（已被覆盖，无法从仓库取回）。
详见 [63-image-upgrade.md](63-image-upgrade.md)。
