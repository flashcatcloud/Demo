#!/usr/bin/env bash
# =============================================================================
# 推送 categraf chart 到 OCI 仓库（仓库地址已固化，勿随意修改）
#   仓库: oci://registry.flashcat.cloud/public/charts
#
# 用法:
#   ./publish-chart.sh                  # 推送最新 categraf-*.tgz
#   ./publish-chart.sh 0.1.11           # 推送指定版本
#   ./publish-chart.sh --login 0.1.11   # 先 helm registry login 再推送（交互输入）
#   ./publish-chart.sh --skip-latest    # 推送后不打 latest 标签
#
# 免交互登录（可选环境变量）:
#   PUBLISH_REGISTRY_USER=xxx PUBLISH_REGISTRY_PASSWORD=yyy ./publish-chart.sh --login 0.1.11
#
# 说明:
#   - helm OCI 使用独立凭据，docker login 不能替代 helm registry login
#   - helm push 只打版本 tag；latest 标签需 oras/crane 补充（自动检测，缺失时给出提示）
#   - 版本号规则：生产用正式版本（如 0.2.1），测试候选用预发布版本（如 0.2.2-rc.1）。
#     预发布版本（版本号带 "-"）无论如何都不会更新 latest，latest 只指向生产 GA 版本。
#   - 禁止同版本覆盖重推（会导致同一 tag 的 digest 漂移，回滚时无法确认内容）；改动必须升版本号。
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

REGISTRY="registry.flashcat.cloud"
REPO="oci://${REGISTRY}/public/charts"
IMG="${REGISTRY}/public/charts/categraf"

LOGIN=0
SKIP_LATEST=0
POS_ARGS=()
for a in "$@"; do
    case "$a" in
        --login)       LOGIN=1 ;;
        --skip-latest) SKIP_LATEST=1 ;;
        *)             POS_ARGS+=("$a") ;;
    esac
done
set -- "${POS_ARGS[@]}"

if [ "$#" -ge 1 ]; then
    VERSION="$1"
    TGZ="categraf-${VERSION}.tgz"
else
    TGZ="$(ls -t categraf-*.tgz 2>/dev/null | head -1 || true)"
fi

if [ -z "${TGZ:-}" ] || [ ! -f "$TGZ" ]; then
    echo "错误：找不到要推送的包（${TGZ:-无}），请先 helm package 或指定版本号：./publish-chart.sh <版本>" >&2
    exit 1
fi
VERSION="${TGZ#categraf-}"
VERSION="${VERSION%.tgz}"

# 预发布版本（0.2.2-rc.1 / 0.2.2-test.1 等）只推版本 tag，不更新 latest。
# latest 只指向生产 GA 版本，避免测试构建被“不写版本号”的用户直接装上。
IS_PRERELEASE=0
case "$VERSION" in
    *-*) IS_PRERELEASE=1 ;;
esac
if [ "$IS_PRERELEASE" = "1" ]; then
    echo "==> 预发布版本 ${VERSION}：不更新 latest（latest 保持指向生产版本）"
fi

if [ "$LOGIN" = "1" ]; then
    if [ -n "${PUBLISH_REGISTRY_USER:-}" ] && [ -n "${PUBLISH_REGISTRY_PASSWORD:-}" ]; then
        echo "==> 登录 ${REGISTRY}（使用环境变量凭据）"
        printf '%s' "$PUBLISH_REGISTRY_PASSWORD" | helm registry login "$REGISTRY" \
            --username "$PUBLISH_REGISTRY_USER" --password-stdin
    else
        echo "==> 登录 ${REGISTRY}（按提示输入用户名/密码）"
        helm registry login "$REGISTRY"
    fi
fi

echo "==> 推送 ${TGZ} -> ${REPO}"
helm push "$TGZ" "$REPO"

echo "==> 验证"
helm show chart "${REPO}/categraf" --version "$VERSION"

if [ "$IS_PRERELEASE" = "1" ]; then
    echo "（预发布版本不打 latest；GA 时用正式版本号再推一次，由那次更新 latest）"
elif [ "$SKIP_LATEST" = "1" ]; then
    echo "（已跳过 latest 标签）"
elif command -v oras >/dev/null 2>&1; then
    echo "==> 打 latest 标签（oras）"
    oras copy "${IMG}:${VERSION}" "${IMG}:latest"
elif command -v crane >/dev/null 2>&1; then
    echo "==> 打 latest 标签（crane）"
    crane tag "${IMG}:${VERSION}" latest
else
    echo "提示：本机没有 oras/crane，无法自动打 latest 标签。"
    echo "      请任选其一："
    echo "        1) brew install oras && oras copy ${IMG}:${VERSION} ${IMG}:latest"
    echo "        2) 在仓库控制台把 categraf:${VERSION} 复制/标记为 latest"
fi

echo "推送完成: ${REPO}/categraf:${VERSION}"
