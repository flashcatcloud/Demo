#!/usr/bin/env bash
# 共享采集函数：categraf 0.2.2-rc.1 回归证据收集
# 依赖：sshpass、curl、jq、security（macOS 钥匙串）、test-env skill 的 flsh.sh / fcapi.sh
set -uo pipefail

REPO_ROOT="/Users/flashcat/Library/Mobile Documents/com~apple~CloudDocs/luomaojian/Demo/k8s-best-practice"
EV="${EV:-$REPO_ROOT/docs/测试验证记录/evidence/20261103-0.2.2-rc.1}"
SSH_TARGET="${SSH_TARGET:-100.98.231.109}"
FLSH="${FLSH:-/Users/flashcat/.codex/skills/test-env/scripts/flsh.sh}"
FCAPI="${FCAPI:-/Users/flashcat/.codex/skills/test-env/scripts/fcapi.sh}"
CLUSTER="${CLUSTER:-k8s-flashcat-test-20261029}"
NS="${NS:-categraf}"
REL="${REL:-categraf}"
SSH_PASS="${SSH_PASS:-$(security find-generic-password -s k8s-test-node1-ssh -a root -w)}"

# SSH 连接复用（大幅降低每条命令的握手开销）
CM_K8S="${CM_K8S:-$HOME/.ssh/cm-k8s-test}"
CM_FC="${CM_FC:-$HOME/.ssh/cm-flashcat-local}"

# 在测试 K8S 主机上执行命令（连接复用；仅 SSH 层故障时重建连接并重试，远端命令非 0 退出码原样返回）
ksi() {
  local out rc
  out=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o LogLevel=ERROR \
    -o ControlMaster=auto -o ControlPath="$CM_K8S" -o ControlPersist=15m \
    root@"$SSH_TARGET" "$@" 2>/tmp/.ksi.err); rc=$?
  if [ $rc -ne 0 ] && grep -qE 'ssh:|Broken pipe|Connection (refused|reset|timed out)|closed by remote' /tmp/.ksi.err 2>/dev/null; then
    rm -f "$CM_K8S"
    out=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=15 -o LogLevel=ERROR -o ControlMaster=auto -o ControlPath="$CM_K8S" -o ControlPersist=15m \
      root@"$SSH_TARGET" "$@" 2>/dev/null); rc=$?
  fi
  printf '%s\n' "$out"; return $rc
}

# 在 Flashcat 主机上执行命令（密钥认证；同上策略）
fssh() {
  local out rc
  out=$(ssh -i "${FLASHCAT_LOCAL_SSH_KEY:-$HOME/.ssh/id_ed25519}" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o LogLevel=ERROR \
    -o ControlMaster=auto -o ControlPath="$CM_FC" -o ControlPersist=15m \
    root@flashcat.local "$@" 2>/tmp/.fssh.err); rc=$?
  if [ $rc -ne 0 ] && grep -qE 'ssh:|Broken pipe|Connection (refused|reset|timed out)|closed by remote' /tmp/.fssh.err 2>/dev/null; then
    rm -f "$CM_FC"
    out=$(ssh -i "${FLASHCAT_LOCAL_SSH_KEY:-$HOME/.ssh/id_ed25519}" -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o LogLevel=ERROR \
      -o ControlMaster=auto -o ControlPath="$CM_FC" -o ControlPersist=15m root@flashcat.local "$@" 2>/dev/null); rc=$?
  fi
  printf '%s\n' "$out"; return $rc
}

# 把本地文件推到测试主机
push() {
  sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$1" root@"$SSH_TARGET":"$2"
}

# Flashcat API（只读）
fca() { "$FCAPI" "$@" 2>/dev/null; }

# 查询 Flashcat 背后的 VictoriaMetrics（返回 JSON）
vmq() {
  local promql="$1" enc payload
  enc=$(python3 -c 'import urllib.parse,sys;sys.stdout.write(urllib.parse.quote(sys.argv[1],safe=""))' "$promql")
  payload="docker exec vmselect sh -c \"wget -qO- \\\"http://127.0.0.1:8481/select/0/prometheus/api/v1/query?query=$enc\\\"\""
  fssh "$payload" 2>/dev/null
}

# 证据文件头：ev <文件> <命令说明>
ev() {
  local file="$1" cmd="$2"
  mkdir -p "$(dirname "$file")"
  {
    echo "# CMD: $cmd"
    echo "# AT: $(date -u +%FT%TZ) / $(date +%FT%T%z)"
    echo
  } >"$file"
}

# 追加一段带标题的原始输出
ev_add() {
  local file="$1" title="$2"
  shift 2
  { echo "### $title"; "$@" 2>&1; echo; } >>"$file"
}

# 断言并记录：pass/fail 同时写入 results.tsv
assert_eq() {
  local name="$1" expected="$2" actual="$3" note="${4:-}"
  local status="PASS"
  [ "$expected" = "$actual" ] || status="FAIL"
  printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$name" "$expected" "$actual" "$note" | tee -a "$EV/results.tsv"
}

assert_ge() {
  local name="$1" min="$2" actual="$3" note="${4:-}"
  local status="PASS"
  python3 -c "import sys;sys.exit(0 if float('$actual') >= float('$min') else 1)" || status="FAIL"
  printf '%s\t%s\t>=%s\t%s\t%s\n' "$status" "$name" "$min" "$actual" "$note" | tee -a "$EV/results.tsv"
}

# 等待命名空间内所有工作负载 Ready
wait_ready() {
  local ns="${1:-$NS}" timeout="${2:-300}"
  ksi "kubectl -n $ns wait --for=condition=Available deploy --all --timeout=${timeout}s 2>&1 | tail -5;
       kubectl -n $ns rollout status ds -l app.kubernetes.io/instance=$REL --timeout=${timeout}s 2>&1 | tail -3;
       kubectl -n $ns rollout status sts --all --timeout=${timeout}s 2>&1 | tail -3"
}
