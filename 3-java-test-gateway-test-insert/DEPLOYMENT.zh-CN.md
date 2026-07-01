# Mock OTel Java 样例程序中文部署说明

这是一份从零开始的现场部署手册。假设部署人员此前不了解这个项目，只要有一台可登录的 Linux 机器、代码包、OTel Collector 地址，就可以按本文档完成部署、启动和验证。

本文档保留英文版 [DEPLOYMENT.md](DEPLOYMENT.md)。中文版本用于现场实施和交付验收。

## 0. 部署目标

部署完成后，目标机器上会运行 3 个 Java 服务：

| 服务名 | 端口 | 作用 |
| --- | ---: | --- |
| `test-gateway` | `8080` | 定时产生业务流量，调用 `test-insert` 和 `test-query` |
| `test-insert` | `8081` | 提供订单写入、更新、删除接口，会写 MySQL |
| `test-query` | `8082` | 提供订单查询接口，会查 MySQL |

同时会安装并使用：

| 组件 | 作用 |
| --- | --- |
| OpenJDK 21 | 运行 Spring Boot 服务 |
| MySQL | 存储样例订单数据 |
| OpenTelemetry Java Agent | 对 Java 服务做自动插桩 |
| systemd | 管理 3 个 Java 服务 |

部署成功后应能在 APM/Trace 页面看到：

```text
test-gateway -> test-insert -> MySQL INSERT/UPDATE/DELETE
test-gateway -> test-query -> MySQL SELECT/GROUP BY
```

日志中应能看到真实 trace 上下文：

```text
trace_id=<32位hex> span_id=<16位hex>
```

## 1. 部署前需要准备什么

### 1.1 目标机器要求

目标机器建议配置：

| 项目 | 要求 |
| --- | --- |
| 操作系统 | Ubuntu 22.04/24.04，或其他 systemd Linux |
| CPU | 2 核及以上 |
| 内存 | 4 GB 及以上 |
| 磁盘 | 至少 10 GB 可用空间 |
| 权限 | 可以使用 root，或具备 sudo 权限 |
| 网络 | 可以访问 OTel Collector；如果使用外部 MySQL，也要能访问该 MySQL |

本文档中的命令默认使用 `root` 执行。如果不是 root，请在需要系统权限的命令前加 `sudo`。

### 1.2 需要开放或确认的端口

目标机器本地端口：

| 端口 | 用途 |
| ---: | --- |
| `3306` | MySQL，仅在本机安装 MySQL 时需要 |
| `8080` | `test-gateway` |
| `8081` | `test-insert` |
| `8082` | `test-query` |

目标机器需要能访问 Collector：

| 地址 | 用途 |
| --- | --- |
| `<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>` | OTLP HTTP/protobuf，上报 trace、metric、log，常见端口为 `4318` 或现场指定端口 |
| `<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_GRPC_PORT>` | OTLP gRPC，备用验证用，常见端口为 `4317` 或现场指定端口 |

本项目不固定 Collector 地址。部署时需要在 `/etc/mock-otel-sample/otel.env` 中填写现场实际地址，例如：

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

说明：测试环境、客户环境的 Collector 地址都可能不同，交付时不要写死任何测试地址，必须替换成现场 Collector 地址。

### 1.3 需要准备的项目文件

部署人员至少需要拿到这个项目目录，目录中应包含：

```text
pom.xml
db/init.sql
deploy/mysql-init.sql
deploy/systemd/mock-test-gateway.service
deploy/systemd/mock-test-insert.service
deploy/systemd/mock-test-query.service
deploy/otel.env.example
deploy/database.env.example
test-gateway/
test-insert/
test-query/
```

检查命令：

```bash
ls -l pom.xml deploy/mysql-init.sql deploy/otel.env.example deploy/database.env.example
ls -l deploy/systemd
ls -d test-gateway test-insert test-query
```

如果这些文件或目录不存在，说明代码包不完整。

## 2. 默认安装路径

服务运行文件会放在：

```text
/opt/mock-otel-sample/
```

具体文件：

```text
/opt/mock-otel-sample/opentelemetry-javaagent.jar
/opt/mock-otel-sample/app/test-gateway-0.0.1-SNAPSHOT.jar
/opt/mock-otel-sample/app/test-insert-0.0.1-SNAPSHOT.jar
/opt/mock-otel-sample/app/test-query-0.0.1-SNAPSHOT.jar
```

日志文件会写到：

```text
/opt/mock-otel-sample/logs/test-gateway/test-gateway.log
/opt/mock-otel-sample/logs/test-insert/test-insert.log
/opt/mock-otel-sample/logs/test-query/test-query.log
```

systemd 服务文件会安装到：

```text
/etc/systemd/system/mock-test-gateway.service
/etc/systemd/system/mock-test-insert.service
/etc/systemd/system/mock-test-query.service
```

## 3. 安装 Java 和基础工具

在目标机器执行：

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jre-headless curl
```

如果准备在目标机器本机安装 MySQL，后面的数据库章节会单独安装 `mysql-server`。
如果选择在目标机器上直接构建 Jar 包，还需要安装 JDK：

```bash
DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk-headless
```

检查 Java：

```bash
java -version
javac -version
```

预期 Java 版本为 17 或更高。推荐 OpenJDK 21。只有运行服务时可以只安装 JRE；如果要执行 `mvn clean package`，必须能正常执行 `javac -version`。

## 4. 创建运行目录

在目标机器执行：

```bash
mkdir -p /etc/mock-otel-sample
mkdir -p /opt/mock-otel-sample/app
mkdir -p /opt/mock-otel-sample/logs/test-gateway /opt/mock-otel-sample/logs/test-insert /opt/mock-otel-sample/logs/test-query
```

检查目录：

```bash
ls -ld /etc/mock-otel-sample
ls -ld /opt/mock-otel-sample/app
ls -ld /opt/mock-otel-sample/logs/test-gateway /opt/mock-otel-sample/logs/test-insert /opt/mock-otel-sample/logs/test-query
```

## 5. 下载 OpenTelemetry Java Agent

在目标机器执行：

```bash
curl -L -o /opt/mock-otel-sample/opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar
```

检查文件：

```bash
ls -lh /opt/mock-otel-sample/opentelemetry-javaagent.jar
```

预期能看到一个几十 MB 的 jar 文件。

如果目标机器不能访问公网，可以在其他能访问公网的机器下载后，再拷贝到：

```text
/opt/mock-otel-sample/opentelemetry-javaagent.jar
```

## 6. 配置 MySQL

`test-insert` 和 `test-query` 需要访问 MySQL。这里有两种方式，任选一种即可。

### 方式 A：使用现场已有 MySQL

如果现场已经有 MySQL，不需要在目标机器安装本地 MySQL。只要准备一个可访问的数据库，并执行初始化 SQL 即可。

外部 MySQL 需要满足：

```text
目标机器可以访问 <MYSQL_HOST>:<MYSQL_PORT>
有一个数据库用户具备建表、查询、插入、更新、删除权限
字符集建议 utf8mb4
```

在外部 MySQL 中创建数据库、用户和表。可以参考 `deploy/mysql-init.sql`，也可以让 DBA 按该 SQL 调整用户名、密码和库名后执行。

然后在目标机器创建数据库连接配置：

```bash
cp deploy/database.env.example /etc/mock-otel-sample/database.env
vi /etc/mock-otel-sample/database.env
```

填写现场实际 MySQL 地址：

```text
DB_URL=jdbc:mysql://<MYSQL_HOST>:<MYSQL_PORT>/<DATABASE_NAME>?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC
DB_USER=<MYSQL_USER>
DB_PASSWORD=<MYSQL_PASSWORD>
```

验证目标机器能连接外部 MySQL：

```bash
mysql -u<MYSQL_USER> -p<MYSQL_PASSWORD> -h<MYSQL_HOST> -P<MYSQL_PORT> <DATABASE_NAME> \
  -e 'SELECT COUNT(*) FROM orders;'
```

如果目标机器没有 `mysql` 客户端，可以安装客户端：

```bash
apt-get install -y mysql-client
```

### 方式 B：在目标机器本机安装 MySQL

如果现场没有现成 MySQL，可以在目标机器本机安装 MySQL：

```bash
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
systemctl enable --now mysql
systemctl is-active mysql
```

预期输出：

```text
active
```

默认数据库信息：

```text
database: order_fulfillment
table: orders
user: mockotel
password: mockotel_pwd
```

在代码目录中执行初始化 SQL：

```bash
mysql < deploy/mysql-init.sql
```

验证数据库：

```bash
mysql -umockotel -pmockotel_pwd -h127.0.0.1 order_fulfillment \
  -e 'SELECT COUNT(*) FROM orders;'
```

预期输出类似：

```text
+----------+
| COUNT(*) |
+----------+
|        0 |
+----------+
```

如果这里失败，先不要启动 Java 服务，优先检查 MySQL 是否 active、`deploy/mysql-init.sql` 是否存在。

本机 MySQL 使用 systemd unit 中的默认连接配置，因此不需要创建 `/etc/mock-otel-sample/database.env`。如果创建了该文件，它会覆盖默认本机连接配置。

## 7. 构建和放置 Jar 包

这里有两种方式，任选一种即可。

### 方式 A：在目标机器上直接构建

如果目标机器可以安装 Maven，可以执行：

```bash
DEBIAN_FRONTEND=noninteractive apt-get install -y maven openjdk-21-jdk-headless
javac -version
```

进入项目目录：

```bash
cd <项目目录>
```

构建：

```bash
mvn clean package
```

预期最后看到：

```text
BUILD SUCCESS
```

复制 jar 到运行目录：

```bash
cp test-gateway/target/test-gateway-0.0.1-SNAPSHOT.jar /opt/mock-otel-sample/app/
cp test-insert/target/test-insert-0.0.1-SNAPSHOT.jar /opt/mock-otel-sample/app/
cp test-query/target/test-query-0.0.1-SNAPSHOT.jar /opt/mock-otel-sample/app/
```

### 方式 B：在本地或构建机上构建，再上传到目标机器

在本地或构建机进入项目目录：

```bash
mvn clean package
```

将 jar 上传到目标机器：

```bash
scp test-gateway/target/test-gateway-0.0.1-SNAPSHOT.jar root@<目标机器IP>:/opt/mock-otel-sample/app/
scp test-insert/target/test-insert-0.0.1-SNAPSHOT.jar root@<目标机器IP>:/opt/mock-otel-sample/app/
scp test-query/target/test-query-0.0.1-SNAPSHOT.jar root@<目标机器IP>:/opt/mock-otel-sample/app/
```

在目标机器检查：

```bash
ls -lh /opt/mock-otel-sample/app/
```

预期至少看到：

```text
test-gateway-0.0.1-SNAPSHOT.jar
test-insert-0.0.1-SNAPSHOT.jar
test-query-0.0.1-SNAPSHOT.jar
```

## 8. 安装 systemd 服务

### 8.1 配置 OTel Collector 地址

3 个服务会从 `/etc/mock-otel-sample/otel.env` 读取 Collector 地址。这个文件必须存在。

在项目目录中执行：

```bash
cp deploy/otel.env.example /etc/mock-otel-sample/otel.env
vi /etc/mock-otel-sample/otel.env
```

将其中的占位符改成现场实际 Collector 地址，例如：

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

例如，现场 Collector 如果给的是 `otel-collector.example.com:4318`，则填写：

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.example.com:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

注意：上面的域名只是示例。实际部署时，应替换成现场 Collector 地址。

启动服务前必须确认 `otel.env` 中没有保留 `<...>` 占位符：

```bash
grep -Eq '^OTEL_EXPORTER_OTLP_ENDPOINT=https?://[^<>[:space:]]+' /etc/mock-otel-sample/otel.env
grep -q '^OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf$' /etc/mock-otel-sample/otel.env
```

如果第一条命令失败，说明 Collector 地址没有填写或仍是占位符。不要继续启动服务；否则服务即使能起来，也可能没有真实 trace 上下文。

### 8.2 安装服务文件

在项目目录中执行：

```bash
cp deploy/systemd/mock-test-gateway.service /etc/systemd/system/
cp deploy/systemd/mock-test-insert.service /etc/systemd/system/
cp deploy/systemd/mock-test-query.service /etc/systemd/system/
```

重新加载 systemd：

```bash
systemctl daemon-reload
```

启动并设置开机自启：

```bash
systemctl enable --now mock-test-insert.service mock-test-query.service mock-test-gateway.service
```

检查状态：

```bash
systemctl is-active mock-test-insert.service mock-test-query.service mock-test-gateway.service
```

预期输出：

```text
active
active
active
```

如果不是 `active`，查看错误：

```bash
systemctl status mock-test-gateway.service mock-test-insert.service mock-test-query.service --no-pager
journalctl -u mock-test-gateway.service -u mock-test-insert.service -u mock-test-query.service -n 200 --no-pager
```

## 9. systemd 中的关键配置说明

3 个服务都通过类似下面的命令启动：

```text
/usr/bin/java -javaagent:/opt/mock-otel-sample/opentelemetry-javaagent.jar -jar /opt/mock-otel-sample/app/<service>.jar
```

关键 OTel 环境变量：

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

`test-insert` 和 `test-query` 还配置了 JDBC 自动插桩：

```text
OTEL_INSTRUMENTATION_JDBC_ENABLED=true
OTEL_INSTRUMENTATION_JDBC_DATASOURCE_ENABLED=true
OTEL_INSTRUMENTATION_JDBC_STATEMENT_SANITIZER_ENABLED=false
OTEL_INSTRUMENTATION_COMMON_DB_STATEMENT_SANITIZER_ENABLED=false
```

说明：

- `OTEL_TRACES_SAMPLER=always_on` 表示所有 trace 都采样。
- `OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED=true` 表示日志中会注入 `trace_id` 和 `span_id`。
- DB statement sanitizer 被关闭，是为了在链路详情中看到更完整的 SQL。
- 服务代码不手动创建 span，HTTP、Spring MVC、定时任务、JDBC 都由 OTel Java Agent 自动插桩。

查看服务实际环境变量：

```bash
systemctl show mock-test-gateway.service -p Environment --no-pager
systemctl show mock-test-insert.service -p Environment --no-pager
systemctl show mock-test-query.service -p Environment --no-pager
```

## 10. 验证服务是否可用

### 10.1 检查端口

```bash
ss -ltnp | grep -E ':8080|:8081|:8082'
```

预期能看到 3 个 Java 进程分别监听：

```text
:8080
:8081
:8082
```

### 10.2 检查健康接口

```bash
curl -sS http://127.0.0.1:8081/api/health
curl -sS http://127.0.0.1:8082/api/health
curl -sS http://127.0.0.1:8080/api/global-view
```

预期：

- `test-insert` 返回 `status=UP`，并包含 `mysql/order_fulfillment.orders`
- `test-query` 返回 `status=UP`，并包含 `mysql/order_fulfillment.orders`
- `test-gateway` 返回全局视图数据

### 10.3 手动触发业务流量

执行：

```bash
curl -sS 'http://127.0.0.1:8080/api/gateway/flow?scenario=checkout&sequence=1001'
curl -sS 'http://127.0.0.1:8080/api/gateway/flow?scenario=browse&sequence=1002'
curl -sS 'http://127.0.0.1:8080/api/gateway/flow?scenario=audit&sequence=1003'
curl -sS 'http://127.0.0.1:8080/api/gateway/flow?scenario=campaign&sequence=1004'
```

这些请求会触发：

| 场景 | 会产生的行为 |
| --- | --- |
| `checkout` | 创建订单、查询订单、更新为已支付、按条件查询 |
| `browse` | 查询订单列表、关键词搜索 |
| `audit` | 查询健康状态、创建待审核订单、审批、创建并删除拒绝订单 |
| `campaign` | 批量创建订单、搜索、按状态聚合 |

`test-gateway` 本身也会每 5 秒自动触发一次下游调用，所以即使不手动 curl，也会持续产生 trace。

## 11. 验证 Java Agent 是否加载

执行：

```bash
ps -ef | grep opentelemetry-javaagent | grep -v grep
```

预期能看到 3 个 Java 进程，并且命令行中包含：

```text
-javaagent:/opt/mock-otel-sample/opentelemetry-javaagent.jar
```

如果没有看到 `-javaagent`，说明不是通过提供的 systemd unit 启动，或 unit 文件未正确安装。

## 12. 验证日志

### 12.1 查看 journal 日志

```bash
journalctl -u mock-test-gateway.service -u mock-test-insert.service -u mock-test-query.service -n 100 --no-pager
```

### 12.2 查看文件日志

```bash
tail -n 50 /opt/mock-otel-sample/logs/test-gateway/test-gateway.log
tail -n 50 /opt/mock-otel-sample/logs/test-insert/test-insert.log
tail -n 50 /opt/mock-otel-sample/logs/test-query/test-query.log
```

### 12.3 验证日志中是否带 trace_id

```bash
grep -hE 'trace_id=[0-9a-f]{32}' \
  /opt/mock-otel-sample/logs/test-gateway/test-gateway.log \
  /opt/mock-otel-sample/logs/test-insert/test-insert.log \
  /opt/mock-otel-sample/logs/test-query/test-query.log | tail -n 20
```

预期日志格式类似：

```text
2026-06-22T21:45:40.621+08:00 INFO  service=test-insert trace_id=125a077ec2131c00c98a9bc82508c006 span_id=1ffbc91fcebbb599 thread=http-nio-8081-exec-8 logger=com.example.insert.InsertService - order created ...
```

业务 mock 日志示例：

```text
catalog browse degradation ... cache_hit_rate=23.4% baseline=85%+ origin_bandwidth=12.7TB/hour ...
risk audit backlog ... pending_review=1847 ... current_p95=42m ...
promotion traffic spike ... qps_multiplier=6.8 ... payment_callback_lag_p95=18s ...
order entered manual review ... risk_score=87.6 matched_rules=[address_change,high_amount,new_device] ...
fulfillment distribution anomaly ... top_status=PAID ...
```

## 13. 验证链路上报

### 13.1 验证 Collector 连通性

执行：

```bash
curl -sv --max-time 5 http://<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>/v1/traces -o /tmp/otel-traces-probe.out
```

预期输出中包含：

```text
HTTP/1.1 405 Method Not Allowed
supported: [POST]
```

这个结果是正常的，因为浏览器式 GET 请求不被 `/v1/traces` 接收，但它说明 OTLP HTTP receiver 是连通的。

### 13.2 从日志中提取 Trace ID

```bash
grep -hE 'trace_id=[0-9a-f]{32}' \
  /opt/mock-otel-sample/logs/test-gateway/test-gateway.log \
  /opt/mock-otel-sample/logs/test-insert/test-insert.log \
  /opt/mock-otel-sample/logs/test-query/test-query.log \
  | tail -n 50 \
  | sed -n 's/.*trace_id=\([0-9a-f]\{32\}\).*/\1/p' \
  | sort -u
```

复制任意一个 Trace ID，到 APM/Trace 页面搜索。

正常情况下应该能看到：

```text
test-gateway
test-insert
test-query
MySQL JDBC span
```

数据库 span 中应包含：

```text
db.system=mysql
db.name=order_fulfillment
db.query.text 或 db.statement 中包含 SQL
```

如果日志中有同一个 `trace_id`，但 UI 中搜索不到，请检查：

- UI 时间范围是否覆盖当前时间。
- 是否选择了正确的数据源、租户或业务组。
- Collector 后端入库是否正常。
- 目标机器到 `<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>` 是否可达。

## 14. 验证数据库操作

执行：

```bash
mysql -umockotel -pmockotel_pwd -h127.0.0.1 order_fulfillment \
  -e 'SELECT id, order_no, customer_id, status, amount, message, source, created_at FROM orders ORDER BY id DESC LIMIT 10;'
```

预期能看到 `test-gateway/...` 来源的订单数据，例如：

```text
source=test-gateway/checkout-order
source=test-gateway/campaign-a
source=test-gateway/audit-correction
```

这说明 `test-insert` 正在写库，`test-query` 查询这些数据时会产生 JDBC SELECT span。

## 15. 常见问题排查

### 15.1 服务不是 active

执行：

```bash
systemctl status mock-test-gateway.service mock-test-insert.service mock-test-query.service --no-pager
journalctl -u mock-test-gateway.service -u mock-test-insert.service -u mock-test-query.service -n 200 --no-pager
```

常见原因：

- Jar 包没有复制到 `/opt/mock-otel-sample/app/`。
- `opentelemetry-javaagent.jar` 不存在。
- MySQL 未启动。
- 端口 `8080/8081/8082` 被占用。
- systemd unit 中的路径写错。

### 15.2 看不到数据库 span

检查环境变量：

```bash
systemctl show mock-test-insert.service mock-test-query.service -p Environment --no-pager
```

确认存在：

```text
OTEL_INSTRUMENTATION_JDBC_ENABLED=true
OTEL_INSTRUMENTATION_JDBC_DATASOURCE_ENABLED=true
```

同时确认服务确实在访问 MySQL：

```bash
curl -sS http://127.0.0.1:8081/api/health
curl -sS http://127.0.0.1:8082/api/health
```

### 15.3 日志没有 trace_id

检查：

```bash
systemctl show mock-test-gateway.service mock-test-insert.service mock-test-query.service -p Environment --no-pager \
  | grep OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED
```

应包含：

```text
OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED=true
```

还要确认日志是在请求上下文中产生的。服务启动日志一般没有 `trace_id`，这是正常现象。
如果请求日志也没有 `trace_id`，继续确认 `/etc/mock-otel-sample/otel.env` 中的 `OTEL_EXPORTER_OTLP_ENDPOINT` 已替换为真实 Collector 地址，不是 `<OTEL_COLLECTOR_HOST>` 占位符。

### 15.4 UI 中看不到 trace

执行：

```bash
ps -ef | grep opentelemetry-javaagent | grep -v grep
curl -sv --max-time 5 http://<OTEL_COLLECTOR_HOST>:<OTEL_COLLECTOR_HTTP_PORT>/v1/traces -o /tmp/otel-traces-probe.out
journalctl -u mock-test-gateway.service -u mock-test-insert.service -u mock-test-query.service --since '10 minutes ago' --no-pager \
  | grep -Ei 'otel|export|otlp|failed|error|exception|timeout|refused|unavailable'
```

如果应用日志中有 `trace_id`，但 UI 搜不到，优先检查 UI 时间范围、租户、数据源和 Collector 后端入库。

### 15.5 临时打开 Java Agent debug 日志

在 3 个 systemd unit 中加入：

```text
Environment=OTEL_JAVAAGENT_DEBUG=true
```

然后执行：

```bash
systemctl daemon-reload
systemctl restart mock-test-insert.service mock-test-query.service mock-test-gateway.service
```

验证完成后建议去掉该配置，避免 debug 日志过多。

## 16. 日志字段提取正则

如果日志系统需要解析这些文件日志，可以使用：

```regex
^(?<time>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2})\s+(?<level>[A-Z]+)\s+service=(?<service>\S+)\s+trace_id=(?<trace_id>[0-9a-f]*)\s+span_id=(?<span_id>[0-9a-f]*)\s+thread=(?<thread>\S+)\s+logger=(?<logger>\S+)\s+-\s+.*
```

如果要求 `trace_id` 和 `span_id` 必须非空，使用更严格版本：

```regex
^(?<time>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2})\s+(?<level>[A-Z]+)\s+service=(?<service>\S+)\s+trace_id=(?<trace_id>[0-9a-f]{32})\s+span_id=(?<span_id>[0-9a-f]{16})\s+thread=(?<thread>\S+)\s+logger=(?<logger>\S+)\s+-\s+.*
```

## 17. 清理环境

停止并禁用服务：

```bash
systemctl disable --now mock-test-gateway.service mock-test-query.service mock-test-insert.service
```

删除样例程序文件：

```bash
rm -rf /opt/mock-otel-sample
rm -f /etc/systemd/system/mock-test-gateway.service
rm -f /etc/systemd/system/mock-test-insert.service
rm -f /etc/systemd/system/mock-test-query.service
systemctl daemon-reload
```

可选：清理 MySQL 数据库和用户：

```bash
mysql -e "DROP DATABASE IF EXISTS order_fulfillment; DROP USER IF EXISTS 'mockotel'@'127.0.0.1';"
```

如果也要移除 MySQL：

```bash
systemctl disable --now mysql
apt-get purge -y mysql-server mysql-client mysql-common
apt-get autoremove -y
```

## 18. 最终验收清单

部署完成后，按下面清单逐项确认：

```text
[ ] mysql 是 active
[ ] /opt/mock-otel-sample/opentelemetry-javaagent.jar 存在
[ ] /opt/mock-otel-sample/app 下有 3 个服务 jar
[ ] mock-test-insert.service 是 active
[ ] mock-test-query.service 是 active
[ ] mock-test-gateway.service 是 active
[ ] 8080、8081、8082 端口已监听
[ ] /api/health 返回 UP
[ ] /opt/mock-otel-sample/logs/test-*/*.log 有日志
[ ] 日志中有 trace_id 和 span_id
[ ] ps 中能看到 -javaagent
[ ] APM/Trace UI 能搜到日志中的 trace_id
[ ] Trace 中有 test-gateway、test-insert、test-query
[ ] Trace 中有 MySQL span，db.system=mysql
[ ] MySQL orders 表中有测试订单数据
```
