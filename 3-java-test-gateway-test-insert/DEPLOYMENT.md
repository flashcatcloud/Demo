# Mock OTel Java Sample Deployment Guide

This guide deploys three Spring Boot services with OpenTelemetry Java Agent auto-instrumentation:

- `test-gateway`: traffic generator and scenario coordinator, port `8080`
- `test-insert`: order write service, port `8081`
- `test-query`: order query service, port `8082`

The services use local MySQL and export telemetry to the OTel Collector.

## 1. Environment Requirements

Target host:

- OS: Ubuntu 22.04/24.04 or another systemd-based Linux distribution
- CPU/Memory: 2 CPU cores and 4 GB memory minimum
- Disk: at least 10 GB free space
- Java: JRE/JDK 17 or later. OpenJDK 21 is recommended
- Database: MySQL 8.x, local or external
- Network:
  - The host can access `<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>` for OTLP HTTP/protobuf
  - Optional: the host can access `<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_GRPC_PORT>` for OTLP gRPC
  - Local ports `8080`, `8081`, and `8082` are available. Local `3306` is required only when MySQL is installed on the target host

Default runtime paths:

```text
/opt/mock-otel-sample/opentelemetry-javaagent.jar
/opt/mock-otel-sample/app/test-gateway-0.0.1-SNAPSHOT.jar
/opt/mock-otel-sample/app/test-insert-0.0.1-SNAPSHOT.jar
/opt/mock-otel-sample/app/test-query-0.0.1-SNAPSHOT.jar
/opt/mock-otel-sample/logs/test-gateway/test-gateway.log
/opt/mock-otel-sample/logs/test-insert/test-insert.log
/opt/mock-otel-sample/logs/test-query/test-query.log
```

Default database:

```text
database: order_fulfillment
table: orders
user: mockotel
password: mockotel_pwd
url: jdbc:mysql://127.0.0.1:3306/order_fulfillment?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC
```

## 2. Install Java and MySQL

Run on the target host:

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jre-headless mysql-server curl
systemctl enable --now mysql
systemctl is-active mysql
java -version
```

Expected:

```text
mysql is active
java version is 17 or later
```

## 3. Initialize Database

Copy the repository or at least `deploy/mysql-init.sql` to the target host, then run:

```bash
mysql < deploy/mysql-init.sql
mysql -umockotel -pmockotel_pwd -h127.0.0.1 order_fulfillment \
  -e 'SELECT COUNT(*) FROM orders;'
```

Expected:

```text
The query succeeds and returns a row count.
```

If you use an existing external MySQL, initialize that database with equivalent SQL and create `/etc/mock-otel-sample/database.env` from [deploy/database.env.example](deploy/database.env.example):

```text
DB_URL=jdbc:mysql://<MYSQL_HOST>:<MYSQL_PORT>/<DATABASE_NAME>?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC
DB_USER=<MYSQL_USER>
DB_PASSWORD=<MYSQL_PASSWORD>
```

## 4. Prepare Runtime Directories

```bash
mkdir -p /etc/mock-otel-sample
mkdir -p /opt/mock-otel-sample/app
mkdir -p /opt/mock-otel-sample/logs/test-gateway /opt/mock-otel-sample/logs/test-insert /opt/mock-otel-sample/logs/test-query
```

## 5. Download OpenTelemetry Java Agent

```bash
curl -L -o /opt/mock-otel-sample/opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar

ls -lh /opt/mock-otel-sample/opentelemetry-javaagent.jar
```

## 6. Build Jars

Build on any machine with Maven and JDK 17+:

```bash
mvn clean package
```

The generated jars are:

```text
test-gateway/target/test-gateway-0.0.1-SNAPSHOT.jar
test-insert/target/test-insert-0.0.1-SNAPSHOT.jar
test-query/target/test-query-0.0.1-SNAPSHOT.jar
```

Copy them to the target host:

```bash
scp test-gateway/target/test-gateway-0.0.1-SNAPSHOT.jar root@<target-host>:/opt/mock-otel-sample/app/
scp test-insert/target/test-insert-0.0.1-SNAPSHOT.jar root@<target-host>:/opt/mock-otel-sample/app/
scp test-query/target/test-query-0.0.1-SNAPSHOT.jar root@<target-host>:/opt/mock-otel-sample/app/
```

## 7. Install systemd Units

Copy these files to `/etc/systemd/system/` on the target host:

```text
deploy/systemd/mock-test-gateway.service
deploy/systemd/mock-test-insert.service
deploy/systemd/mock-test-query.service
```

Then run:

```bash
cp deploy/otel.env.example /etc/mock-otel-sample/otel.env
# Edit /etc/mock-otel-sample/otel.env and set the real Collector endpoint.
systemctl daemon-reload
systemctl enable --now mock-test-insert.service mock-test-query.service mock-test-gateway.service
systemctl is-active mock-test-insert.service mock-test-query.service mock-test-gateway.service
```

Expected:

```text
active
active
active
```

## 8. Important OTel Settings

The provided systemd units read the Collector endpoint from `/etc/mock-otel-sample/otel.env` and use:

```text
OTEL_SERVICE_NAME=test-gateway/test-insert/test-query
OTEL_EXPORTER_OTLP_ENDPOINT=http://<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_TRACES_SAMPLER=always_on
OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED=true
```

`test-insert` and `test-query` also use:

```text
OTEL_INSTRUMENTATION_JDBC_ENABLED=true
OTEL_INSTRUMENTATION_JDBC_DATASOURCE_ENABLED=true
OTEL_INSTRUMENTATION_JDBC_STATEMENT_SANITIZER_ENABLED=false
OTEL_INSTRUMENTATION_COMMON_DB_STATEMENT_SANITIZER_ENABLED=false
```

The DB statement sanitizer is disabled so the trace view can show readable SQL text. The services do not manually create spans. HTTP, Spring MVC, scheduling, JDBC, and log MDC are provided by the OTel Java Agent.

## 9. Verify Services

Check ports:

```bash
ss -ltnp | grep -E ':8080|:8081|:8082'
```

Check health:

```bash
curl -sS http://127.0.0.1:8081/api/health
curl -sS http://127.0.0.1:8082/api/health
curl -sS http://127.0.0.1:8080/api/global-view
```

Trigger traffic:

```bash
curl -sS 'http://127.0.0.1:8080/api/gateway/flow?scenario=checkout&sequence=1001'
curl -sS 'http://127.0.0.1:8080/api/gateway/flow?scenario=browse&sequence=1002'
curl -sS 'http://127.0.0.1:8080/api/gateway/flow?scenario=audit&sequence=1003'
curl -sS 'http://127.0.0.1:8080/api/gateway/flow?scenario=campaign&sequence=1004'
```

Check the Java Agent:

```bash
ps -ef | grep opentelemetry-javaagent | grep -v grep
```

Expected:

```text
All three Java processes contain -javaagent:/opt/mock-otel-sample/opentelemetry-javaagent.jar
```

## 10. Verify Logs

Journal:

```bash
journalctl -u mock-test-gateway.service -u mock-test-insert.service -u mock-test-query.service -n 100 --no-pager
```

File logs:

```bash
tail -n 50 /opt/mock-otel-sample/logs/test-gateway/test-gateway.log
tail -n 50 /opt/mock-otel-sample/logs/test-insert/test-insert.log
tail -n 50 /opt/mock-otel-sample/logs/test-query/test-query.log
```

Verify trace context in logs:

```bash
grep -hE 'trace_id=[0-9a-f]{32}' \
  /opt/mock-otel-sample/logs/test-gateway/test-gateway.log \
  /opt/mock-otel-sample/logs/test-insert/test-insert.log \
  /opt/mock-otel-sample/logs/test-query/test-query.log | tail -n 20
```

Business mock logs should look like:

```text
catalog browse degradation ... cache_hit_rate=23.4% baseline=85%+ origin_bandwidth=12.7TB/hour ...
risk audit backlog ... pending_review=1847 ... current_p95=42m ...
promotion traffic spike ... qps_multiplier=6.8 ... payment_callback_lag_p95=18s ...
order entered manual review ... risk_score=87.6 matched_rules=[address_change,high_amount,new_device] ...
fulfillment distribution anomaly ... top_status=PAID ...
```

## 11. Verify Traces

Collector connectivity:

```bash
curl -sv --max-time 5 http://<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>/v1/traces -o /tmp/otel-traces-probe.out
```

Expected:

```text
HTTP/1.1 405 Method Not Allowed
supported: [POST]
```

This means the OTLP HTTP receiver is reachable.

Extract recent Trace IDs from logs:

```bash
grep -hE 'trace_id=[0-9a-f]{32}' \
  /opt/mock-otel-sample/logs/test-gateway/test-gateway.log \
  /opt/mock-otel-sample/logs/test-insert/test-insert.log \
  /opt/mock-otel-sample/logs/test-query/test-query.log \
  | tail -n 50 \
  | sed -n 's/.*trace_id=\([0-9a-f]\{32\}\).*/\1/p' \
  | sort -u
```

Search one of those Trace IDs in the trace UI. A healthy trace should include:

```text
test-gateway -> test-insert -> MySQL INSERT/UPDATE/DELETE
test-gateway -> test-query -> MySQL SELECT/GROUP BY
```

Database spans should show:

```text
db.system=mysql
db.name=order_fulfillment
db.query.text or db.statement contains SQL
```

## 12. Troubleshooting

If services are not active:

```bash
systemctl status mock-test-gateway.service mock-test-insert.service mock-test-query.service --no-pager
journalctl -u mock-test-gateway.service -u mock-test-insert.service -u mock-test-query.service -n 200 --no-pager
```

If DB spans are missing:

```bash
systemctl show mock-test-insert.service mock-test-query.service -p Environment --no-pager
```

Confirm these are present:

```text
OTEL_INSTRUMENTATION_JDBC_ENABLED=true
OTEL_INSTRUMENTATION_JDBC_DATASOURCE_ENABLED=true
```

If traces are not visible in the UI:

```bash
ps -ef | grep opentelemetry-javaagent | grep -v grep
curl -sv --max-time 5 http://<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>/v1/traces -o /tmp/otel-traces-probe.out
journalctl -u mock-test-gateway.service -u mock-test-insert.service -u mock-test-query.service --since '10 minutes ago' --no-pager \
  | grep -Ei 'otel|export|otlp|failed|error|exception|timeout|refused|unavailable'
```

If needed, temporarily enable Java Agent debug logs in the systemd unit:

```text
Environment=OTEL_JAVAAGENT_DEBUG=true
```

Then run:

```bash
systemctl daemon-reload
systemctl restart mock-test-insert.service mock-test-query.service mock-test-gateway.service
```

## 13. Cleanup

Stop services:

```bash
systemctl disable --now mock-test-gateway.service mock-test-query.service mock-test-insert.service
```

Remove sample files:

```bash
rm -rf /opt/mock-otel-sample
rm -f /etc/systemd/system/mock-test-gateway.service
rm -f /etc/systemd/system/mock-test-insert.service
rm -f /etc/systemd/system/mock-test-query.service
systemctl daemon-reload
```

Optional MySQL cleanup:

```bash
mysql -e "DROP DATABASE IF EXISTS order_fulfillment; DROP USER IF EXISTS 'mockotel'@'127.0.0.1';"
```
