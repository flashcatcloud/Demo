#!/usr/bin/env bash
# G1 包与静态验证（不修改集群）
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh
PKG="$REPO_ROOT/categraf-0.2.2-rc.2.tgz"
OLD="$REPO_ROOT/categraf-0.2.2-rc.1.tgz"
F="$EV/01b-static-rc2.md"
# 追加到同一 results.tsv（rc.2 为最终交付包）

render() { helm template t "$PKG" --kube-version "${KV:-1.28.2}" --set operator.userToken=tok "$@" 2>&1; }

ev "$F" "G1 static: helm show/lint/render，包=$PKG"

# ---------- 1.1 包元数据 ----------
{
  echo "## 1.1 包元数据"
  echo '```'
  echo '$ helm show chart categraf-0.2.2-rc.1.tgz'
  helm show chart "$PKG"
  echo
  echo '$ shasum -a 256 / ls -l'
  shasum -a 256 "$PKG"; ls -l "$PKG"
  echo
  echo '$ tar tzf (文件清单)'
  tar tzf "$PKG"
  echo '```'
} >>"$F"
assert_eq "1.1-version" "0.2.2-rc.2" "$(helm show chart "$PKG" | awk '/^version:/{print $2}')"
assert_eq "1.1-appVersion" "0.5.32" "$(helm show chart "$PKG" | awk '/^appVersion:/{print $2}' | tr -d '"')"
assert_eq "1.1-kubeVersion" "'>=1.19.0-0 <1.38.0-0'" "$(helm show chart "$PKG" | awk '/^kubeVersion:/{$1="";print substr($0,2)}')"
assert_eq "1.1-sha256" "82ec6041ce9e953d9dffc5255bb51892041787d61e04e0996f0fa41f69778e5e" "$(shasum -a 256 "$PKG" | awk '{print $1}')"
assert_eq "1.1-无杂项文件" "0" "$(tar tzf "$PKG" | grep -cE '\.DS_Store|\.git/|\.codex' || true)"

# ---------- 1.2 lint ----------
{
  echo "## 1.2 helm lint（3 组 values）"
  echo '```'
  for f in "" "-f $REPO_ROOT/assets/categraf-helm/categraf/values-examples/values.yaml" "-f $REPO_ROOT/assets/categraf-helm/categraf/values-examples/values.all.yaml"; do
    echo "--- helm lint $f ---"
    # shellcheck disable=SC2086
    helm lint "$REPO_ROOT/assets/categraf-helm/categraf" $f 2>&1 | tail -3
  done
  echo '```'
} >>"$F"

# ---------- 1.3 与 0.2.4 包的内容等价性 ----------
REGV=(
  --set categraf.serverAddr=http://192.168.31.14:19000
  --set categraf.clusterName=k8s-flashcat-test-20261029
  --set categraf.env=test
  --set categraf.config.interval=20
  --set categraf.writer.batch=3000
  --set categraf.writer.chanSize=1500000
  --set categraf.heartbeat.interval=12
  --set categraf.heartbeat.timeout=6000
  --set categraf.heartbeat.dialTimeout=3000
  --set-json 'categraf.customLabels={"environment":"test","owner":"platform"}'
)
helm template t "$OLD" --kube-version 1.28.2 --set operator.userToken=tok "${REGV[@]}" 2>/dev/null \
  | sed -E 's#helm\.sh/chart: .*#helm.sh/chart: NORM#; s#app\.kubernetes\.io/version: .*#app.kubernetes.io/version: NORM#; s#checksum/config: .*#checksum/config: NORM#' >"$EV/_render-old.yaml"
render "${REGV[@]}" \
  | sed -E 's#helm\.sh/chart: .*#helm.sh/chart: NORM#; s#app\.kubernetes\.io/version: .*#app.kubernetes.io/version: NORM#; s#checksum/config: .*#checksum/config: NORM#' >"$EV/_render-new.yaml"
{
  echo "## 1.3 内容等价性：0.2.4 包 vs 0.2.2-rc.1 包（同一组 values，归一化版本标签后 diff）"
  echo '```'
  echo "\$ diff -u <(render 0.2.4) <(render 0.2.2-rc.1)   # 归一化 helm.sh/chart 与 app.kubernetes.io/version"
  diff -u "$EV/_render-old.yaml" "$EV/_render-new.yaml" && echo "(无差异)"
  echo
  echo "渲染行数: old=$(wc -l <"$EV/_render-old.yaml") new=$(wc -l <"$EV/_render-new.yaml")"
  echo '```'
} >>"$F"
assert_eq "1.3-与0.2.4渲染等价" "0" "$(diff -u "$EV/_render-old.yaml" "$EV/_render-new.yaml" | wc -l | tr -d ' ')"

# ---------- 1.4 kubeVersion 矩阵 ----------
{
  echo "## 1.4 kubeVersion 矩阵"
  echo '```'
  for v in 1.18.0 1.19.0 1.20.0 1.21.0 1.28.2 1.30.0 1.31.0 1.32.0 1.34.0 1.36.0 1.37.0 1.37.2 1.38.0; do
    out=$(helm template t "$PKG" --kube-version "$v" --set operator.userToken=tok 2>&1 >/dev/null)
    if [ -z "$out" ]; then echo "$v  OK"; else echo "$v  REJECT  $(echo "$out" | head -1 | cut -c1-110)"; fi
  done
  echo '```'
} >>"$F"

# ---------- 1.5 负向用例 ----------
NEG="$EV/03b-negative-rc2.md"
ev "$NEG" "G1 负向用例：每个用例必须渲染失败且报错文案匹配"
neg() { # neg <name> <期望错误子串> <helm args...>
  local name="$1" expect="$2"; shift 2
  local out code
  out=$(helm template t "$PKG" --kube-version 1.28.2 "$@" 2>&1 >/dev/null); code=$?
  local got; got=$(echo "$out" | head -2 | tr '\n' ' ' | cut -c1-200)
  if [ "$code" -ne 0 ] && echo "$out" | grep -qF -- "$expect"; then
    echo "$name OK (exit=$code)" ; printf 'PASS\t%s\t%s\t%s\t%s\n' "$name" "$expect" "render-fail" "$got" >>"$EV/results.tsv"
  else
    echo "$name FAIL (exit=$code) expect=[$expect] got=[$got]"; printf 'FAIL\t%s\t%s\t%s\t%s\n' "$name" "$expect" "render-fail" "$got" >>"$EV/results.tsv"
  fi
  { echo "### $name"; echo '```'; echo "期望错误含: $expect"; echo "$out" | head -3; echo '```'; } >>"$NEG"
}
{
  echo "# 负向用例原始输出"; echo
} >>"$NEG"
neg "interval=0" "categraf.config.interval must be greater than 0" --set operator.userToken=tok --set categraf.config.interval=0
neg "interval=-1" "categraf.config.interval must be greater than 0" --set operator.userToken=tok --set categraf.config.interval=-1
neg "batch=-1" "categraf.writer.batch must be greater than or equal to 0" --set operator.userToken=tok --set categraf.writer.batch=-1
neg "chanSize=0" "categraf.writer.chanSize must be greater than 0" --set operator.userToken=tok --set categraf.writer.chanSize=0
neg "heartbeat.interval=0" "categraf.heartbeat.interval must be greater than 0" --set operator.userToken=tok --set categraf.heartbeat.interval=0
neg "heartbeat.timeout=0" "categraf.heartbeat.timeout must be greater than 0" --set operator.userToken=tok --set categraf.heartbeat.timeout=0
neg "heartbeat.dialTimeout=0" "categraf.heartbeat.dialTimeout must be greater than 0" --set operator.userToken=tok --set categraf.heartbeat.dialTimeout=0
neg "customLabels 覆盖 cluster" "cannot override reserved label" --set operator.userToken=tok --set-json 'categraf.customLabels={"cluster":"x"}'
neg "customLabels 覆盖 env" "cannot override reserved label" --set operator.userToken=tok --set-json 'categraf.customLabels={"env":"x"}'
neg "customLabels 覆盖 categraf" "cannot override reserved label" --set operator.userToken=tok --set-json 'categraf.customLabels={"categraf":"x"}'
neg "customLabels 非法键 foo-bar" "is not a valid Prometheus label name" --set operator.userToken=tok --set-json 'categraf.customLabels={"foo-bar":"x"}'
neg "customLabels 值为 map" "must be a string, number or boolean" --set operator.userToken=tok --set-json 'categraf.customLabels={"region":{"a":"b"}}'
neg "operator 无 userToken" "operator.userToken 必填" --set operator.enabled=true
neg "extraScrapeConfigs 非 list" "appMetrics.extraScrapeConfigs must be a list" --set operator.userToken=tok --set appMetrics.extraScrapeConfigs=notalist
# 正向：batch=0 允许并回落各组件默认
{
  echo "### 正向 batch=0（允许，回落 Node=2000 / KSM=1000）"
  echo '```'
  render --set categraf.writer.batch=0 | grep -E '^\s+(batch|chan_size)' | head -4
  echo '```'
} >>"$NEG"
assert_eq "batch=0 回落 Node=2000" "1" "$(render --set categraf.writer.batch=0 | grep -c 'batch = 2000')"
assert_eq "batch=0 回落 KSM=1000" "1" "$(render --set categraf.writer.batch=0 | grep -c 'batch = 1000')"

# ---------- 1.6 开关矩阵 ----------
SW="$EV/04b-toggles-rc2.md"
ev "$SW" "G1 开关矩阵：每个开关关闭/开启时的资源增减"
toggle() { # toggle <name> <期望描述> <grep 模式> <期望出现次数> <helm args...>
  local name="$1" expect="$2" pat="$3" cnt="$4"; shift 4
  local out got
  out=$(render "$@")
  got=$(echo "$out" | grep -cE "$pat" || true)
  assert_eq "toggle-$name" "$cnt" "$got" "$expect"
  echo "### ${name} -> 匹配 /${pat}/ = ${got} (期望 ${cnt}: ${expect})" >>"$SW"
}
{
  echo "默认渲染资源清单："; echo '```'
  render | grep -E '^kind:' | sort | uniq -c
  echo '```'; echo
} >>"$SW"
toggle "默认-DaemonSet" "默认安装 node agent" '^kind: DaemonSet' 1
toggle "默认-StatefulSet" "默认安装 ksm agent" '^kind: StatefulSet' 1
toggle "默认-Deployment" "kube-state-metrics + operator" '^kind: Deployment' 2
toggle "nodeAgent-off-DS" "nodeCategraf.enabled=false 不产生 DaemonSet" '^kind: DaemonSet' 0 --set nodeCategraf.enabled=false
toggle "nodeAgent-off-config" "对应 configmap 也消失" 'name: t-config$' 0 --set nodeCategraf.enabled=false
toggle "ksmAgent-off-STS" "ksmCategraf.enabled=false 不产生 StatefulSet" '^kind: StatefulSet' 0 --set ksmCategraf.enabled=false
toggle "ksm-off-appMetrics-job" "ksm 关闭时 app-metrics job 随之消失" "job_name: 'app-metrics'" 0 --set ksmCategraf.enabled=false
toggle "ksm-off-coreDns-job" "ksm 关闭时 coredns job 随之消失" "job_name: 'coredns'" 0 --set ksmCategraf.enabled=false
toggle "ksm-metrics-job-off" "jobs.kubeStateMetrics=false 移除 KSM job" "job_name: 'kube-state-metrics'" 0 --set ksmCategraf.jobs.kubeStateMetrics=false
toggle "ksm-off" "kubeStateMetrics.enabled=false 移除 Deployment/Service" 'name: t-kube-state-metrics$' 0 --set kubeStateMetrics.enabled=false
toggle "operator-off" "operator.enabled=false 不产生 operator 资源" 'name: t-operator$' 0 --set operator.enabled=false
toggle "operator-cleanup-hook" "cleanup 两开关均 true 时 4 个 hook 资源带 pre-delete" 'helm.sh/hook": pre-delete' 4
toggle "operator-cleanup-off" "cleanup 均 false 时无 hook Job" 'kind: Job' 0 --set operator.cleanup.nodeCategraf=false --set operator.cleanup.ksmCategraf=false
toggle "appMetrics-off" "appMetrics.enabled=false 无 app-metrics job" "job_name: 'app-metrics'" 0 --set appMetrics.enabled=false
toggle "coreDns-off" "coreDns.enabled=false 无 coredns job" "job_name: 'coredns'" 0 --set coreDns.enabled=false
toggle "kubeProxy-off" "kubeProxy.enabled=false 无 kube-proxy 输入" 'input.prometheus/kube-proxy.toml' 0 --set kubeProxy.enabled=false
toggle "networkPlugin-off" "calico/cilium 都关则无对应 job" 'job_name: .(calico|cilium).' 0 --set networkPlugin.calico.enabled=false --set networkPlugin.cilium.enabled=false
toggle "controlPlane-on" "controlPlane.enabled=true 增加 4 个控制平面 job" 'job_name: .(apiserver|kube-controller-manager|kube-scheduler|etcd).' 4 --set controlPlane.enabled=true
toggle "cadvisor-off" "inputs.cadvisor=false 去掉 cadvisor 输入" 'input.prometheus/cadvisor.toml' 0 --set nodeCategraf.inputs.cadvisor=false
toggle "nodeExporter-off" "inputs.nodeExporter=false 去掉 node_exporter 输入" 'categraf-input-node-exporter' 0 --set nodeCategraf.inputs.nodeExporter=false
toggle "hostExec-off" "hostExec.enabled=false 不挂 ibex" 'name: ibex-host-meta' 0 --set nodeCategraf.hostExec.enabled=false

# ---------- 1.7 资源约定断言 ----------
RC="$EV/05b-conventions-rc2.md"
ev "$RC" "G1 资源约定断言（命名/镜像/权限/挂载）"
R=$(render)
{
  echo '## 默认渲染中的关键约定'; echo '```'
  echo '--- 资源名 ---'; echo "$R" | grep -E '^\s+name: t-' | sort -u | head -30
  echo '--- 镜像 ---'; echo "$R" | grep -E 'image: ' | sort -u
  echo '--- ClusterRole 名 ---'; echo "$R" | grep -A2 'kind: ClusterRole$' | grep 'name:'
  echo '--- selector / instance 标签 ---'; echo "$R" | grep -cE 'app.kubernetes.io/instance: t'
  echo '--- hostNetwork/hostPID ---'; echo "$R" | grep -cE 'hostNetwork: true|hostPID: true'
  echo '--- hostfs 挂载 ---'; echo "$R" | grep -c 'mountPath: /hostfs'
  echo '--- syslog 禁用 configmap ---'; echo "$R" | grep -c 'disable-syslog'
  echo '--- hello' >/dev/null
  echo '```'
} >>"$RC"
assert_eq "镜像-categraf_ent(ksm)" "1" "$(echo "$R" | grep -c 'image: "registry.flashcat.cloud/public/categraf_ent:v0.5.32"' || true)"
assert_eq "镜像-servicemap(node)" "1" "$(echo "$R" | grep -c 'servicemap-v0.5.32' || true)"
assert_eq "镜像-ksm" "1" "$(echo "$R" | grep -c 'kube-state-metrics:v2.19.1' || true)"
assert_eq "镜像-operator(operator Deployment+cleanup Job 各 1)" "2" "$(echo "$R" | grep -c 'categraf-operator:0.0.7' || true)"
assert_eq "hostNetwork+hostPID" "2" "$(echo "$R" | grep -cE 'hostNetwork: true|hostPID: true' || true)"
assert_eq "hostfs 挂载(node agent 容器)" "1" "$(echo "$R" | grep -c 'mountPath: /hostfs' || true)"
assert_eq "hostfs 宿主根挂载" "1" "$(echo "$R" | grep -c 'path: /$' || true)"
assert_eq "ClusterRole 数量(ksm/operator/node-agent)" "3" "$(echo "$R" | grep -A2 '^kind: ClusterRole$' | grep -cE 'name: t-default-(kube-state-metrics|operator|node-agent)' || true)"
# 每个 workload/service 的 selector 都必须带 instance 标签（共 5 个 selector 块）
assert_eq "selector 块数量且均含 instance" "5" "$(echo "$R" | awk '/^  selector:/{s=NR} s && NR<=s+6 && /app.kubernetes.io\/instance: t/{c++; s=0} END{print c+0}')"

# ---------- 1.8 边界观察：serverAddr 尾斜杠 ----------
{
  echo "## 1.8 边界观察：serverAddr 带尾斜杠"
  echo '```'
  render --set categraf.serverAddr=http://192.168.31.14:19000/ | grep -E 'address=|url =|url:' | head -6
  echo '```'
} >>"$F"

echo "G1 完成：$F / $NEG / $SW / $RC"
grep -c PASS "$EV/results.tsv" | xargs echo "PASS 条数:"
grep FAIL "$EV/results.tsv" | head -10 || true
