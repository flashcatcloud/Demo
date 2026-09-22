# 发布 Chart 到 OCI 仓库（固定地址）

本项目的 categraf chart **推送目标仓库已固化**，后续「推送到仓库」一律指：

| 项 | 值 |
|---|---|
| Chart | `categraf`（包名由 `Chart.yaml` 决定，勿写到地址里） |
| 仓库地址 | `oci://registry.flashcat.cloud/public/charts` |
| 登录 | `helm registry login registry.flashcat.cloud` |
| 当前版本 | `0.2.1`（已推送并更新 latest） |

## 一键推送（推荐）

```bash
./publish-chart.sh            # 推送最新的 categraf-*.tgz
./publish-chart.sh 0.2.1      # 推送指定版本
```

## 手动命令

```bash
helm registry login registry.flashcat.cloud
helm push categraf-0.2.1.tgz oci://registry.flashcat.cloud/public/charts

# 验证
helm show chart oci://registry.flashcat.cloud/public/charts/categraf --version 0.2.1
```

## latest 标签（文档默认拉取的就是它）

- `helm push` 只会打**版本标签**（如 `0.2.1`），不会自动生成 `latest`。
- `publish-chart.sh` 推送成功后会尝试用 `oras` / `crane` 把该版本复制为 `latest`；本机没装这两个工具时会打印提示，按提示补打即可。
- 文档里的 `oci://registry.flashcat.cloud/public/charts/categraf`（不带 `--version`）即拉取 `latest`，因此**每次发版后务必让 latest 指向最新版本**，文档里的示例命令无需再写死版本号。

## 注意

- 地址写到 `.../public/charts` 这一层即可，**不要**写成 `.../charts/categraf`（最后的 `categraf` 由 chart 名自动决定）。
- 登录账号需有 `public/charts` 的**写入权限**。
- 发布前确认 `Chart.yaml` 版本号。本次 `0.2.1` 经确认执行同版本覆盖，推送后必须同步更新 `latest`，并记录新的 Chart Digest，避免新旧内容混用。
