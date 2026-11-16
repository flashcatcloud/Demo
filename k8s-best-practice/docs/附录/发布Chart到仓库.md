# 发布 Chart 到 OCI 仓库（固定地址）

本项目的 categraf chart **推送目标仓库已固化**，后续「推送到仓库」一律指：

| 项 | 值 |
|---|---|
| Chart | `categraf`（包名由 `Chart.yaml` 决定，勿写到地址里） |
| 仓库地址 | `oci://registry.flashcat.cloud/public/charts` |
| 登录 | `helm registry login registry.flashcat.cloud` |
| 生产版本 | `0.2.3`（`latest` 指向它，2026-11-16 发布；上一版 `0.2.2` 保留可回退） |
| 回归执行包 | `0.2.3` 为正式发布；历史回归包 `0.2.2-rc.3`（SHA256 `633fd00a…`）仅作记录保留 |

## 版本号规则

版本号是**发布身份**，不是测试迭代计数器。规则：

| 场景 | 版本号 | 示例 |
|---|---|---|
| 生产已发布 | 正式版本，不复用、不覆盖 | `0.2.1` |
| 下一正式版本 | 生产版本 + 1 个 patch（功能新增也是 patch 位，因为处于 0.x） | `0.2.4` |
| 测试候选 | 下一正式版本 + 预发布后缀，后缀序号递增 | `0.2.2-rc.1`、`0.2.2-rc.2` |
| 其他测试通道（可选） | `-test.<日期>.<序号>` | `0.2.4-test.20261120.1` |

- semver 排序上 `0.2.2-rc.1 < 0.2.2`，因此测试候选先推不会挡住正式版，正式版发布时天然比所有 rc 新。
- **一次测试迭代只递增后缀**，不要因为改了几行就 bump 成 `0.2.3`、`0.2.4`——那会让版本号失去“这是第几个发布版本”的含义，也会让生产版本号和候选版本号混在一起。
- **禁止同版本覆盖重推**。同一个 tag 推第二次会让 digest 漂移，回滚时无法确认那个版本到底是哪份内容（`0.2.1` 的历史记录里就出现过同版本覆盖）。
- `appVersion` 跟随被部署的应用版本，当前为 categraf 镜像版本 `0.5.32`，不要留占位值 `1.0.0`。
- `categraf-0.2.2.tgz`、`categraf-0.2.3.tgz` 为**已发布版本**对应的包；`0.2.2-rc.*` 为回归候选（rc 不更新 `latest`）；`0.2.4` 曾为内部测试构建，已从工作区清理，不要引用。

## 一键推送（推荐）

```bash
./publish-chart.sh                # 推送最新的 categraf-*.tgz
./publish-chart.sh 0.2.3         # 推送指定版本
```

`publish-chart.sh` 对预发布版本（版本号含 `-`）会自动**跳过 latest**，只打版本 tag。

## 手动命令

```bash
helm registry login registry.flashcat.cloud
helm push categraf-0.2.3.tgz oci://registry.flashcat.cloud/public/charts

# 验证
helm show chart oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.3
```

## latest 标签（文档默认拉取的就是它）

- `helm push` 只会打**版本标签**（如 `0.2.2-rc.1`），不会自动生成 `latest`。
- `latest` **只允许指向生产 GA 版本**。预发布版本不打 latest，避免“不写版本号”的用户直接装上测试构建。
- 当前 `latest` = `0.2.3`，digest `sha256:3f1166eafcc6cde19d7585fc8ebea67f7474c67eac6c038a147baf31ee4d9106`（2026-11-16 发布）。核对命令：

  ```bash
  helm show chart oci://registry.flashcat.cloud/public/charts/categraf | grep '^version:'
  ```

- 只有正式版本发布时，`publish-chart.sh` 才用 `oras` / `crane` 把该版本复制为 `latest`；本机没装这两个工具时会打印提示，按提示补打即可。
- 正式版发布后，文档里不带 `--version` 的 `helm pull` 即拉取 latest，示例命令无需写死版本号；需要固定版本时显式写 `--version`。

## 注意

- 地址写到 `.../public/charts` 这一层即可，**不要**写成 `.../charts/categraf`（最后的 `categraf` 由 chart 名自动决定）。
- 登录账号需有 `public/charts` 的**写入权限**。
- 发布前确认 `Chart.yaml` 的 `version` / `appVersion` / `kubeVersion` 三项都已更新，并记录新的 Chart SHA256 与 OCI Digest，避免新旧内容混用。
- 测试候选版本需要测试环境拉取时，显式写 `--version 0.2.2-rc.1`；不要依赖 latest。
