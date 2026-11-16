#!/usr/bin/env bash
# G9 交付包溯源：文档更新后重新打包，证明与已回归包“仅文档差异”
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/55-repack.md"
PKG="$REPO_ROOT/categraf-0.2.2-rc.1.tgz"
OLD=/tmp/rc1-before-docs.tgz
CHART_DIR="$REPO_ROOT/assets/categraf-helm/categraf"

ev "$F" "G9 交付包溯源：运行回归用的包 vs 文档更新后重新打的包"
cp "$PKG" "$OLD"
OLD_SHA=$(shasum -a 256 "$OLD" | awk '{print $1}')
rm -f "$PKG"
helm package "$CHART_DIR" -d "$REPO_ROOT" >/dev/null
NEW_SHA=$(shasum -a 256 "$PKG" | awk '{print $1}')
EX=/tmp/pkgex; rm -rf "$EX"; mkdir -p "$EX/old" "$EX/new"
tar xzf "$OLD" -C "$EX/old"; tar xzf "$PKG" -C "$EX/new"
{
  echo "## G9.1 两个包的 SHA256"; echo '```'
  echo "运行回归的包(before docs): $OLD_SHA  ($(wc -c <"$OLD" | tr -d ' ') bytes)"
  echo "文档更新后重新打包(new):   $NEW_SHA  ($(wc -c <"$PKG" | tr -d ' ') bytes)"
  echo '```'
  echo "## G9.2 差异文件清单（应只有 README.md）"; echo '```'
  echo '$ diff -r old new'
  diff -r "$EX/old/categraf" "$EX/new/categraf" >/tmp/repack-diff.txt 2>&1 && echo '(无差异)' || sed -E 's#/tmp/pkgex/(old|new)/categraf/##; s#^(diff -r|Only in) [^ ]+ ?##' /tmp/repack-diff.txt | head -20
  echo "差异文件数: $(grep -cE '^diff ' /tmp/repack-diff.txt || true)  新增/缺失: $(grep -cE '^Only in' /tmp/repack-diff.txt || true)"
  echo '```'
  echo "## G9.3 运行时内容等价性（同一组 values 渲染 diff）"; echo '```'
  RM=(--set categraf.serverAddr=http://192.168.31.14:19000 --set categraf.clusterName=k8s-flashcat-test-20261029 --set categraf.env=test --set operator.userToken=tok)
  helm template t "$OLD" --kube-version 1.28.2 "${RM[@]}" 2>/dev/null | sed -E 's#helm\.sh/chart: .*#NORM#; s#app\.kubernetes\.io/version: .*#NORM#; s#checksum/config: .*#NORM#' >/tmp/render-before.yaml
  helm template t "$PKG" --kube-version 1.28.2 "${RM[@]}" 2>/dev/null | sed -E 's#helm\.sh/chart: .*#NORM#; s#app\.kubernetes\.io/version: .*#NORM#; s#checksum/config: .*#NORM#' >/tmp/render-after.yaml
  if diff -q /tmp/render-before.yaml /tmp/render-after.yaml >/dev/null; then echo "(渲染结果完全一致，$(( $(wc -l < /tmp/render-before.yaml) )) 行)"; else diff /tmp/render-before.yaml /tmp/render-after.yaml | head -20; fi
  echo '```'
  echo "## G9.4 新包 lint / 元数据"; echo '```'
  helm lint "$PKG" 2>&1 | tail -2
  helm show chart "$PKG" | grep -E '^(version|appVersion|kubeVersion):'
  echo '```'
} >"$F"
assert_eq "G9-差异文件仅 README" "0" "$(diff -r -x README.md "$EX/old/categraf" "$EX/new/categraf" 2>&1 | wc -l | tr -d ' ')"
assert_eq "G9-渲染结果一致" "0" "$(diff /tmp/render-before.yaml /tmp/render-after.yaml | wc -l | tr -d ' ')"
assert_eq "G9-新包 lint 通过" "1" "$(helm lint "$PKG" 2>&1 | grep -c '0 chart(s) failed')"
echo "G9 完成: $F"; echo "OLD_SHA=$OLD_SHA"; echo "NEW_SHA=$NEW_SHA"
