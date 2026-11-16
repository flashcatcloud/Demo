# CMD: 发布 0.2.2-rc.3 到 OCI 仓库（预发布，不更新 latest）
# AT: 2026-11-03T07:36:31Z / 2026-11-03T15:36:31+0800

## 1. 推前仓库状态
```
latest = 0.2.1；0.2.2-rc.1/rc.2/rc.3 均不存在（rc.1/rc.2 从未推送）
```
## 2. 执行发布（publish-chart.sh 0.2.2-rc.3）
```
Pushed: registry.flashcat.cloud/public/charts/categraf:0.2.2-rc.3
Digest: sha256:4fcdbaa12e141aacb4b34405d13e1a349ce612b28506f58ae7742c17dc6270b9
Digest: sha256:4fcdbaa12e141aacb4b34405d13e1a349ce612b28506f58ae7742c17dc6270b9
（预发布版本不打 latest；GA 时用正式版本号再推一次，由那次更新 latest）
推送完成: oci://registry.flashcat.cloud/public/charts/categraf:0.2.2-rc.3
```
## 3. 推后校验
```
远端拉回包 SHA256 = 633fd00acec54ba298702cd4f656405f7a7d1e444161f9c214b2158a68d7a00d
本地包   SHA256 = 633fd00acec54ba298702cd4f656405f7a7d1e444161f9c214b2158a68d7a00d
→ 远端包与本地包 完全一致

仓库标签状态（latest 未被预发布版本改动）:
  latest = 0.2.1
  0.2.2-rc.3 = 已存在

OCI manifest Digest（helm push 输出）: sha256:4fcdbaa12e141aacb4b34405d13e1a349ce612b28506f58ae7742c17dc6270b9
```
## 4. 结论
```
rc.3 已作为预发布版本推送，latest 仍指向生产版本 0.2.1；
预发布守卫生效（脚本自动跳过 latest）。正式版 0.2.2 发布时用正式版本号再推一次，由那次更新 latest。
```
