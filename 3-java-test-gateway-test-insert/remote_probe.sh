set -e
printf 'HOSTNAME='
hostname
printf 'OS='
head -n1 /etc/os-release 2>/dev/null || uname -a
printf 'ARCH='
uname -m
if command -v java >/dev/null 2>&1; then
  java -version 2>&1 | head -n3
else
  echo JAVA_MISSING
fi
command -v curl || true
command -v wget || true
command -v yum || true
command -v apt-get || true
command -v ss || true
timeout 3 bash -lc 'cat < /dev/null > /dev/tcp/10.99.1.6/4418' && echo COLLECTOR_4418_OK || echo COLLECTOR_4418_FAIL
timeout 3 bash -lc 'cat < /dev/null > /dev/tcp/10.99.1.6/4417' && echo COLLECTOR_4417_OK || echo COLLECTOR_4417_FAIL
