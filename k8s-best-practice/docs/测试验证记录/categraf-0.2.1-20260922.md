# Categraf 0.2.1 覆盖更新验证

## 1. 基本信息

| 项 | 值 |
|---|---|
| 测试日期 | 2026-09-22 |
| 变更范围 | Chart-only；Release selector 隔离、cleanup 默认开启、Operator 资源限制进入示例 values |
| Chart | `categraf-0.2.1`，同版本覆盖 |
| Operator | `registry.flashcat.cloud/public/categraf-operator:0.0.7`，未修改 |
| Chart SHA256 | `7dbd6db0b16a4f13bc18a83f7a2c5f34ac7a3ebe319d39c56ddcdf5fa042b731` |
| 上一版 selector 包 SHA256 | `ad29dd6c0dfbc0f7e8adf75d961c88019c7046d88f99853ea5667b9a549fb239` |
| 旧 Chart SHA256 | `101f2978a5f547d4f4316b806bbe953722ad144147b4bb4744293b89fe64af69` |
| OCI Digest | `sha256:f816e2331d1ccda9aed641b7b41abf892a69af012b264c5108fb41743292eefc` |
| 测试命名空间 | `categraf` |
| 测试结果 | 通过 |

## 2. 测试环境

| 项 | 值 |
|---|---|
| Flashcat | `100.73.244.81:19000` |
| Agent 服务端地址 | `http://192.168.31.14:19000` |
| Kubernetes | `v1.28.2` |
| k8s-node1 | `192.168.31.5`，control-plane |
| k8s-node2 | `192.168.31.6`，worker |
| OS | Ubuntu 22.04.5 LTS |
| Container Runtime | containerd 2.2.1 |
| Helm | v3.21.3 |

## 3. 验证步骤与结果

| 步骤 | 结果 |
|---|---|
| `helm lint` | 通过 |
| 单 Release/双 Release 模板渲染 isolation 检查 | 通过，selector 包含 Release，Pod 标签匹配 |
| `go test ./...` | 通过 |
| `go vet ./...` | 通过 |
| 备份现有 values、manifest、Secret 和旧 Chart | 通过，保存在测试节点备份目录 |
| 临时开启旧 Release 设备清理并卸载 | 通过，旧 Node/KSM 设备删除后数量为 0 |
| 安装修改后 Chart 0.2.1 | 通过，5 个 Pod Running/Ready |
| 检查 workload/Service selector | 通过，均包含 `app.kubernetes.io/instance=categraf` |
| 检查 KSM Endpoint | 通过，只包含本 Release 的 KSM Pod |
| 检查 Operator Leader Lease | 通过，成功持有 `categraf-node-cleanup.flashcat.io` |
| 检查 Operator 资源限制 | 通过，requests `100m/64Mi`，limits `500m/256Mi` |
| 检查 cleanup 默认值 | 通过，`nodeCategraf=true`、`ksmCategraf=true` |
| 检查 Flashcat 上报 | 通过，恢复 2 个 NodeAgent 和 1 个 KSMAgent，`target_up=2` |
| 默认配置卸载 | 通过，Flashcat 本集群设备清理后数量为 0 |
| 使用默认配置重新安装 | 通过，测试环境恢复正常运行 |
| 恢复后清理开关 | `true true`，符合新默认值 |

## 4. 影响与限制

- Deployment、StatefulSet、DaemonSet 的 selector 不可变；已有旧 `0.2.1` Release 不能直接 `helm upgrade`。
- 升级必须执行：备份 values -> 卸载旧 Release -> 安装新 Release。
- 全新安装不受影响。
- 当前 Chart 仍按“一个集群一个 Release”运行。
- Operator leader election Lease 仍使用固定名称，不支持同 namespace 多 Release 的完整隔离。
- Node Agent 默认 ident 仍为节点名，以满足 servicemap 要求；同一 Flashcat、同一节点上运行多个 Release 仍可能发生设备 ident 冲突。

## 5. 发布结果

| 项 | 结果 |
|---|---|
| 推送目标 | `oci://registry.flashcat.cloud/public/charts` |
| `0.2.1` Digest | `sha256:f816e2331d1ccda9aed641b7b41abf892a69af012b264c5108fb41743292eefc` |
| `latest` | 已验证与 `0.2.1` 指向同一 Digest |
| 远端包 SHA256 | `7dbd6db0b16a4f13bc18a83f7a2c5f34ac7a3ebe319d39c56ddcdf5fa042b731`，与本地包一致 |
| Operator 镜像 | 未发布、未覆盖，保持 `0.0.7` |

## 6. 回滚

- 测试节点备份目录：`/root/categraf-backup-20260922-220403`。
- 原始 values、manifest、Secret 和旧 Chart 包均已备份。
- Operator `0.0.7` 未变更，可继续使用。
- 回滚步骤：卸载当前 Release，使用备份 values 和旧 `categraf-0.2.1.tgz` 重新安装。
