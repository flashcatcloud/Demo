#!/usr/bin/env bash
# 证据包复跑入口：categraf 0.2.2-rc.1 完整回归
#   ./run-checks.sh G0   环境基线快照（只读）
#   ./run-checks.sh G1   包与静态验证（只读，纯本地 helm 渲染）
#   ./run-checks.sh G2   生命周期：卸载清理→装0.2.1→升级rc.1→回滚（**会删除/重建 Flashcat 设备**）
#   ./run-checks.sh G3   核心数据链路（只读）
#   ./run-checks.sh G4   配置面功能矩阵（**会多次 helm upgrade，改动测试集群**）
#   ./run-checks.sh G5   韧性与自愈（**会删除 Pod 触发重建**）
#   ./run-checks.sh G6   打包与发布面（只读，只依赖 helm 渲染与 stub）
#   ./run-checks.sh G7   文档一致性（只读）
#   ./run-checks.sh G8a  证据自审（只读）
#   ./run-checks.sh G8b  生成 MANIFEST（只读）
#   ./run-checks.sh ro   只跑只读组：G1 G3 G6 G7 G8a G8b
#
# 前置条件：
#   - macOS 上可访问 100.98.231.109（sshpass + 钥匙串 k8s-test-node1-ssh）与 flashcat.local（~/.ssh/id_ed25519）
#   - 本地 helm / jq / python3；测试主机 helm 3.21.3
#   - 环境变量可覆盖：SSH_TARGET、CLUSTER、NS、REL、REPO_ROOT
set -uo pipefail
cd "$(dirname "$0")"
chmod +x *.sh 2>/dev/null || true
group="${1:-ro}"
case "$group" in
  G0) ./g0.sh ;;
  G1) ./g1.sh ;;
  G1b) ./g1rc2.sh ;;   # rc.2 静态回归
  F1) ./f1fix-verify.sh ;;  # F1 修复端到端复验（会创建独立 namespace）
  G9b) ./g9b.sh ;;
  G2) ./g2.sh ;;
  G3) ./g3.sh ;;
  G4) ./g4b.sh ;;
  G5) ./g5.sh ;;
  G6) ./g6.sh ;;
  G7) ./g7.sh ;;
  G8a) ./g8a.sh ;;
  G8b) ./g8b.sh ;;
  ro) for g in g1 g3 g6 g7 g8a g8b; do echo "=== $g ==="; ./$g.sh || true; done ;;
  *) echo "用法: ./run-checks.sh G0|G1|G2|G3|G4|G5|G6|G7|G8a|G8b|ro" >&2; exit 1 ;;
esac
