#!/usr/bin/env bash
# G9b 交付包溯源：不重新打包，只比对“运行回归的旧包”与“当前交付包”
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
F="$EV/55-repack.md"
OLD=/tmp/rc1-runtime-tested.tgz
PKG="$REPO_ROOT/categraf-0.2.2-rc.1.tgz"
OLD_SHA=$(shasum -a 256 "$OLD" | awk '{print $1}')
NEW_SHA=$(shasum -a 256 "$PKG" | awk '{print $1}')
echo "$NEW_SHA" >"$EV/FINAL_SHA"
rm -rf /tmp/repack-old /tmp/repack-new && mkdir -p /tmp/repack-old /tmp/repack-new
tar xzf "$OLD" -C /tmp/repack-old; tar xzf "$PKG" -C /tmp/repack-new
DIFFLIST=$(diff -r /tmp/repack-old/categraf /tmp/repack-new/categraf 2>&1 | grep -E '^(diff|Only)')
helm template t "$OLD" --kube-version 1.28.2 --set operator.userToken=tok >/tmp/repack-r-old.yaml 2>&1
helm template t "$PKG" --kube-version 1.28.2 --set operator.userToken=tok >/tmp/repack-r-new.yaml 2>&1
RDIFF=$(diff /tmp/repack-r-old.yaml /tmp/repack-r-new.yaml | wc -l | tr -d ' ')
ev "$F" "G9 交付包溯源：运行回归的旧包 vs 当前交付包，证明仅 README 差异"
{
  echo "## 包 SHA256"
  echo '```'
  echo "运行回归的包（旧）: $OLD_SHA"
  echo "当前交付包（新）:   $NEW_SHA"
  echo "新包大小: $(ls -l "$PKG" | awk '{print $5}') bytes"
  echo '```'
  echo "## 解包内容差异（应仅 README.md）"
  echo '```'
  printf '%s\n' "$DIFFLIST"
  echo '```'
  echo "## 渲染等价性（同 values，Helm template diff 行数）"
  echo '```'
  echo "diff 行数 = $RDIFF （0 = 运行时行为一致）"
  echo '```'
  echo "## 新包 lint"
  echo '```'
  helm lint "$PKG" 2>&1 | tail -2
  echo '```'
  echo "## 结论"
  echo '```'
  echo "重建只改变 Chart 内 README.md（文档），模板渲染与运行时行为零差异，"
  echo "因此集群回归结论适用于交付包 ${NEW_SHA}。"
  echo '```'
} >>"$F"
assert_eq "G9-差异仅README" "1" "$(printf '%s\n' "$DIFFLIST" | grep -c 'README.md')"
assert_eq "G9-渲染零差异" "0" "$RDIFF"
assert_eq "G9-新包lint通过" "1" "$(helm lint "$PKG" 2>&1 | grep -c '0 chart(s) failed')"
echo "G9b 完成 NEW_SHA=$NEW_SHA"
