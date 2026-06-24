# Mock OTel Three-Service Java Sample

This sample contains three Java modules:

- `test-gateway`: scheduled caller. It periodically calls `test-insert` and `test-query`.
- `test-insert`: HTTP API that writes rows into the database.
- `test-query`: HTTP API that queries rows from the database.

The sample can be started with the OpenTelemetry Java agent for real auto-instrumentation. It also keeps a small mock topology endpoint and page so acceptance testers can verify object relationships even before connecting a collector.

## Ports

| Module | Port | API |
| --- | ---: | --- |
| `test-gateway` | `8080` | scheduled calls only |
| `test-insert` | `8081` | `POST /api/orders`, `PUT /api/orders/{id}/status`, `DELETE /api/orders/{id}` |
| `test-query` | `8082` | `GET /api/orders`, `GET /api/orders/{id}`, `GET /api/orders/search`, `GET /api/orders/stats` |

Extra observability endpoints:

| Module | API | Purpose |
| --- | --- | --- |
| all modules | `GET /api/health` | service, host, database health snapshot |
| all modules | `GET /mock/metrics` | Prometheus-like demo metrics |
| `test-gateway` | `GET /api/global-view` | global view source data |
| `test-gateway` | `GET /` | Web global view page |

## Database

Default DB is a local MySQL database:

```text
jdbc:mysql://127.0.0.1:3306/order_fulfillment?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC
```

The initialization SQL is in [db/init.sql](db/init.sql). For a fresh host, use [deploy/mysql-init.sql](deploy/mysql-init.sql) to create the database, user, privileges, and `orders` table.

To use another database, override:

```bash
DB_URL='jdbc:mysql://127.0.0.1:3306/order_fulfillment?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC'
DB_USER=mockotel
DB_PASSWORD=mockotel_pwd
```

## Build

```bash
mvn clean package
```

## Run

Start the three modules in separate terminals from the repository root:

```bash
mvn -pl test-insert spring-boot:run
```

```bash
mvn -pl test-query spring-boot:run
```

```bash
mvn -pl test-gateway spring-boot:run
```

`test-gateway` calls downstream services every 5 seconds by default. Change the interval with:

```bash
GATEWAY_DELAY_MS=10000 mvn -pl test-gateway spring-boot:run
```

Open the global view page:

```text
http://localhost:8080/
```

The page renders APIs, services, database, hosts, abnormal object, impact scope, and trace/log/metric context from `GET /api/global-view`.

## Run With OpenTelemetry Java Agent

Build executable Spring Boot jars:

```bash
mvn clean package
```

Download `opentelemetry-javaagent.jar` from the OpenTelemetry Java instrumentation release page, then configure the collector endpoint:

```bash
source deploy/otel-javaagent.env.example
export OTEL_JAVAAGENT=/absolute/path/opentelemetry-javaagent.jar
export OTEL_EXPORTER_OTLP_ENDPOINT=http://your-collector:4318
```

Start the services in three terminals:

```bash
bash deploy/run-insert.sh
```

```bash
bash deploy/run-query.sh
```

```bash
bash deploy/run-gateway.sh
```

Each script starts the same business jar with:

```text
-javaagent:${OTEL_JAVAAGENT}
-Dotel.service.name=test-gateway|test-insert|test-query
-Dotel.exporter.otlp.endpoint=...
-Dotel.resource.attributes=deployment.environment=demo,service.namespace=java-sample,host.name=...
```

With the Java agent enabled, the platform under test should collect:

- metrics: JVM, HTTP server/client, process/runtime metrics, plus `/mock/metrics` if scraped
- logs: application logs and mock OTel lines printed by the sample, with `trace_id` and `span_id` in the log pattern when the Java agent injects Logback MDC
- traces: scheduled gateway flow, HTTP client/server spans, JDBC spans for insert/query

Expected trace relationships:

```text
test-gateway scheduled task -> GET /api/gateway/flow -> test-gateway HTTP server
test-gateway -> POST /api/orders -> test-insert -> MySQL INSERT orders
test-gateway -> PUT /api/orders/{id}/status -> test-insert -> MySQL UPDATE orders WHERE id = ?
test-gateway -> DELETE /api/orders/{id} -> test-insert -> MySQL DELETE orders WHERE id = ?
test-gateway -> GET /api/orders/{id} -> test-query -> MySQL SELECT orders WHERE id = ?
test-gateway -> GET /api/orders?status=PAID&customerId=... -> test-query -> MySQL filtered list
test-gateway -> GET /api/orders/search?keyword=... -> test-query -> MySQL keyword/time-window search
test-gateway -> GET /api/orders/stats -> test-query -> MySQL GROUP BY status
```

The gateway intentionally cycles through several scenarios (`checkout`, `browse`, `audit`, and `campaign`) so traces do not all have the same span count. The gateway scheduler calls its own HTTP endpoint first, which gives `test-gateway` real server-side traffic in APM service lists.

In the trace view, the database spans should show `db.system=mysql`. SQL text visibility depends on the collector/backend policy. This sample starts the Java agent with DB statement sanitization disabled in the provided systemd units:

```text
OTEL_INSTRUMENTATION_JDBC_STATEMENT_SANITIZER_ENABLED=false
OTEL_INSTRUMENTATION_COMMON_DB_STATEMENT_SANITIZER_ENABLED=false
```

Application logs use the same console and file pattern in every module:

```text
service=<service-name> trace_id=<otel-trace-id> span_id=<otel-span-id> thread=<thread-name> logger=<logger> - <message>
```

Each service also writes rolling log files under `/datafc/<service>/logs/`:

```text
/datafc/test-gateway/logs/test-gateway.log
/datafc/test-insert/logs/test-insert.log
/datafc/test-query/logs/test-query.log
```

The default rolling policy keeps 14 days, rolls at 100 MB per file, and caps total archived logs at 2 GB per service.

The systemd units set `OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED=true` so the OpenTelemetry Java agent injects the active trace context into Logback MDC. Custom mock OTel lines are emitted through SLF4J, not raw `System.out`, so they also include `trace_id` and `span_id`.

## Fresh Ubuntu Host Deployment

These steps are the intended runbook when a customer gives you a fresh Ubuntu host.

### 1. Install Java and MySQL

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jre-headless mysql-server curl
systemctl enable --now mysql
systemctl is-active mysql
```

This installs a persistent local MySQL service. It creates system files under `/etc/mysql`, `/var/lib/mysql`, and `/var/log/mysql`, and listens on local port `3306`.

### 2. Initialize MySQL

Copy this repository to the host, then run:

```bash
mysql < deploy/mysql-init.sql
mysql -umockotel -pmockotel_pwd -h127.0.0.1 order_fulfillment -e 'SELECT COUNT(*) FROM orders;'
```

The sample database connection is:

```text
database: order_fulfillment
user: mockotel
password: mockotel_pwd
table: orders
```

### 3. Download the OpenTelemetry Java Agent

```bash
mkdir -p /opt/mock-otel-sample/app
mkdir -p /datafc/test-gateway/logs /datafc/test-insert/logs /datafc/test-query/logs
curl -L -o /opt/mock-otel-sample/opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar
```

### 4. Build and Copy Jars

Build locally or on the host:

```bash
mvn clean package
```

Copy the three executable jars to:

```text
/opt/mock-otel-sample/app/test-gateway-0.0.1-SNAPSHOT.jar
/opt/mock-otel-sample/app/test-insert-0.0.1-SNAPSHOT.jar
/opt/mock-otel-sample/app/test-query-0.0.1-SNAPSHOT.jar
```

### 5. Install systemd Units

The included units read the collector endpoint from `/etc/mock-otel-sample/otel.env`. Create it before starting services:

```bash
mkdir -p /etc/mock-otel-sample
cp deploy/otel.env.example /etc/mock-otel-sample/otel.env
```

Set the customer collector address in that file:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

For external MySQL, also create `/etc/mock-otel-sample/database.env` from `deploy/database.env.example`. If that file is absent, the services use the local MySQL defaults.

Copy the files from [deploy/systemd](deploy/systemd) to `/etc/systemd/system`, then run:

```bash
systemctl daemon-reload
systemctl enable --now mock-test-insert.service mock-test-query.service mock-test-gateway.service
systemctl is-active mock-test-insert.service mock-test-query.service mock-test-gateway.service
```

### 6. Verify

```bash
curl -sS -X POST http://127.0.0.1:8081/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"orderNo":"ORD-VERIFY-001","customerId":"customer-demo","status":"CREATED","amount":128.50,"message":"deploy verify","source":"curl"}'

curl -sS http://127.0.0.1:8082/api/orders?status=CREATED
curl -sS http://127.0.0.1:8080/api/global-view

mysql -umockotel -pmockotel_pwd -h127.0.0.1 order_fulfillment \
  -e 'SELECT id, order_no, customer_id, status, amount, message, source, created_at FROM orders ORDER BY id DESC LIMIT 5;'

ps -ef | grep opentelemetry-javaagent | grep -v grep

journalctl -u mock-test-gateway.service -u mock-test-insert.service -u mock-test-query.service -n 80 --no-pager \
  | grep 'trace_id='

tail -n 20 /datafc/test-gateway/logs/test-gateway.log
tail -n 20 /datafc/test-insert/logs/test-insert.log
tail -n 20 /datafc/test-query/logs/test-query.log
```

Expected results:

- all three systemd services are `active`
- `POST /api/orders` returns `status=inserted`
- `GET /api/orders` returns the inserted row
- MySQL query returns the same row
- Java process command line contains `-javaagent:/opt/mock-otel-sample/opentelemetry-javaagent.jar`
- recent journal logs contain `trace_id=<32 hex chars>` and `span_id=<16 hex chars>` for request/scheduler logs
- `/datafc/test-gateway/logs`, `/datafc/test-insert/logs`, and `/datafc/test-query/logs` contain service log files with the same `trace_id` and `span_id` fields

### 7. Cleanup

If the machine must be restored after validation:

```bash
systemctl disable --now mock-test-gateway.service mock-test-query.service mock-test-insert.service
systemctl disable --now mysql
apt-get purge -y mysql-server mysql-client mysql-common
apt-get autoremove -y
```

Delete sample files if needed:

```bash
rm -rf /opt/mock-otel-sample /datafc/test-gateway /datafc/test-insert /datafc/test-query /etc/systemd/system/mock-test-*.service
```

## Acceptance Mapping

| Requirement | Where to verify |
| --- | --- |
| three Java modules | parent `pom.xml` modules: `test-gateway`, `test-insert`, `test-query` |
| gateway periodically calls insert/query | `test-gateway/src/main/java/com/example/gateway/GatewayTask.java` |
| insert writes database | `POST /api/orders`, `PUT /api/orders/{id}/status`, `DELETE /api/orders/{id}`, `test-insert/src/main/java/com/example/insert/InsertService.java` |
| query reads database | `GET /api/orders`, `GET /api/orders/{id}`, `GET /api/orders/search`, `GET /api/orders/stats`, `test-query/src/main/java/com/example/query/QueryController.java` |
| database initialization SQL | `db/init.sql`, module `schema.sql` files |
| deployment docs | this README and `deploy/*.sh` |
| metrics/logs/traces collection | OpenTelemetry Java agent startup plus `/mock/metrics` and application logs |
| Web global view | `http://localhost:8080/` and `GET /api/global-view` |
| API/service/database/host/abnormal/impact/context | nodes and impact sections in the global view |

## Manual Calls

```bash
curl -X POST http://localhost:8081/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"orderNo":"ORD-MANUAL-001","customerId":"customer-demo","status":"CREATED","amount":99.90,"message":"manual insert","source":"curl"}'
```

```bash
curl http://localhost:8082/api/orders/search?keyword=manual
```

## Application Log Output

The Java agent is responsible for trace creation and cross-service propagation. Application logs are normal SLF4J/Logback lines enriched by the Java agent MDC fields. INFO/WARN logs intentionally look like business and troubleshooting signals, not hand-written spans:

```text
service=test-gateway trace_id=<otel-trace-id> span_id=<otel-span-id> promotion traffic spike scenario=campaign qps_multiplier=6.8 stock_reservation_success=91.2% ...
service=test-insert trace_id=<otel-trace-id> span_id=<otel-span-id> order entered manual review order_id=... risk_score=87.6 matched_rules=[address_change,high_amount,new_device] ...
service=test-query trace_id=<otel-trace-id> span_id=<otel-span-id> fulfillment distribution anomaly source_prefix=test-gateway top_status=PAID ...
```

Low-level operation timing logs are DEBUG-only. Do not use handwritten `traceparent` headers for this sample. Let the OpenTelemetry Java agent inject and extract context automatically.
