package com.example.gateway;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
class GlobalViewController {
    @GetMapping("/global-view")
    Map<String, Object> globalView() {
        return orderedMap(
                "generatedAt", Instant.now().toString(),
                "scenario", "test-gateway schedules insert and query requests with mock OTel context propagation",
                "nodes", nodes(),
                "edges", edges(),
                "telemetry", telemetry(),
                "impact", impact(),
                "acceptance", List.of(
                        "API, services, database, hosts, abnormal objects and impact scope are present",
                        "Object relationships match the test data flow",
                        "Metrics, logs and trace context are exposed by the sample"));
    }

    private List<Map<String, Object>> nodes() {
        List<Map<String, Object>> nodes = new ArrayList<>();
        nodes.add(node("api-insert", "API", "POST /api/orders", "UP", "Creates order rows"));
        nodes.add(node("api-query", "API", "GET /api/orders", "UP", "Reads order rows"));
        nodes.add(node("svc-gateway", "SERVICE", "test-gateway", "UP", "Scheduled caller"));
        nodes.add(node("svc-insert", "SERVICE", "test-insert", "UP", "Database writer"));
        nodes.add(node("svc-query", "SERVICE", "test-query", "UP", "Database reader"));
        nodes.add(node("db-events", "DATABASE", "order_fulfillment.orders", "UP", "MySQL orders table"));
        nodes.add(node("host-gateway", "HOST", "sample-host-gateway", "UP", "Runs gateway"));
        nodes.add(node("host-a", "HOST", "sample-host-a", "UP", "Runs insert service"));
        nodes.add(node("host-b", "HOST", "sample-host-b", "UP", "Runs query service"));
        nodes.add(node("exception-slow-query", "ABNORMAL", "mock slow query", "WARN", "Demo abnormal object for impact view"));
        return nodes;
    }

    private Map<String, Object> node(String id, String type, String name, String status, String description) {
        return orderedMap(
                "id", id,
                "type", type,
                "name", name,
                "status", status,
                "description", description);
    }

    private List<Map<String, Object>> edges() {
        return List.of(
                edge("svc-gateway", "api-insert", "calls"),
                edge("svc-gateway", "api-query", "calls"),
                edge("api-insert", "svc-insert", "handled_by"),
                edge("api-query", "svc-query", "handled_by"),
                edge("svc-insert", "db-events", "writes"),
                edge("svc-query", "db-events", "reads"),
                edge("svc-gateway", "host-gateway", "runs_on"),
                edge("svc-insert", "host-a", "runs_on"),
                edge("svc-query", "host-b", "runs_on"),
                edge("exception-slow-query", "svc-query", "affects"),
                edge("exception-slow-query", "db-events", "suspected_scope"));
    }

    private Map<String, Object> edge(String source, String target, String relation) {
        return orderedMap("source", source, "target", target, "relation", relation);
    }

    private Map<String, Object> telemetry() {
        return orderedMap(
                "metrics", List.of(
                        "GET /mock/metrics on each service exposes mock_service_up",
                        "test-insert/test-query expose mock_db_events_total",
                        "test-gateway exposes mock_downstream_dependency_total"),
                "logs", List.of(
                        "service=test-insert trace_id=... span_id=... order created order_id=... status=PAID warehouse=shanghai-01",
                        "service=test-query trace_id=... span_id=... fulfillment distribution anomaly source_prefix=test-gateway top_status=PAID ...",
                        "service=test-gateway trace_id=... span_id=... promotion traffic spike qps_multiplier=6.8 ..."),
                "traces", List.of(
                        "gateway.scheduled.tick -> GET /api/gateway/flow -> POST /api/orders -> db.insert orders",
                        "GET /api/orders/{id} -> SELECT ... WHERE id = ?",
                        "GET /api/orders/stats -> SELECT ... WHERE source LIKE ? GROUP BY status"));
    }

    private Map<String, Object> impact() {
        return orderedMap(
                "abnormalObject", "mock slow query",
                "status", "WARN",
                "affectedApis", List.of("GET /api/orders", "GET /api/orders/search", "GET /api/orders/stats"),
                "affectedServices", List.of("test-query"),
                "affectedDatabase", "order_fulfillment.orders",
                "context", List.of(
                        "test-gateway periodically calls test-query",
                        "test-query reads the shared orders table",
                        "OpenTelemetry Java agent propagates W3C trace context across services"));
    }

    private Map<String, Object> orderedMap(Object... keyValues) {
        Map<String, Object> map = new LinkedHashMap<>();
        for (int i = 0; i < keyValues.length; i += 2) {
            map.put(String.valueOf(keyValues[i]), keyValues[i + 1]);
        }
        return map;
    }
}
