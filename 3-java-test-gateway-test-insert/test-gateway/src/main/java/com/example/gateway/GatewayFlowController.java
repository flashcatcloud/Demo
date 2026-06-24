package com.example.gateway;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

@RestController
@RequestMapping("/api/gateway")
class GatewayFlowController {
    private static final org.slf4j.Logger LOGGER = org.slf4j.LoggerFactory.getLogger(GatewayFlowController.class);
    private final RestClient restClient;
    private final GatewayProperties properties;

    GatewayFlowController(RestClient restClient, GatewayProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    @GetMapping("/flow")
    Map<String, Object> flow(@RequestParam(name = "scenario", defaultValue = "checkout") String scenario,
                             @RequestParam(name = "sequence", defaultValue = "0") long sequence) {
        List<String> actions = new ArrayList<>();
        logScenarioStart(scenario, sequence);
        switch (scenario) {
            case "browse" -> {
                callList(actions, "browse-created", "CREATED", null, null);
                callSearch(actions, "browse-search", "order");
                LOGGER.warn("catalog browse degradation scenario={} sequence={} cache_hit_rate=23.4% baseline=85%+ "
                                + "origin_bandwidth=12.7TB/hour suspected_reason=\"cache rule drift or cache avalanche\" "
                                + "suggestion=\"check Cache-Control and Expires headers\" runbook=https://docs.cdn.internal/troubleshooting#cache-miss",
                        scenario, sequence);
            }
            case "audit" -> {
                callQueryHealth(actions);
                long id = callInsert(actions, sequence, "audit-correction", "PENDING_REVIEW");
                callDetail(actions, id, "audit-detail");
                callUpdateStatus(actions, id, "APPROVED", "audit-approved");
                callList(actions, "audit-approved-list", "APPROVED", null, null);
                long rejectedId = callInsert(actions, sequence, "audit-rejected", "REJECTED");
                callDelete(actions, rejectedId, "audit-delete-rejected");
                LOGGER.warn("risk audit backlog scenario={} sequence={} pending_review=1847 rejected_sample_order_id={} "
                                + "manual_review_sla=15m current_p95=42m impact=\"high value orders delayed\" "
                                + "suggestion=\"check risk-rule version and reviewer queue capacity\"",
                        scenario, sequence, rejectedId);
            }
            case "campaign" -> {
                callInsert(actions, sequence, "campaign-a", "CREATED");
                callInsert(actions, sequence, "campaign-b", "PAID");
                callInsert(actions, sequence, "campaign-c", "SHIPPED");
                callSearch(actions, "campaign-search", "campaign");
                callStats(actions, "campaign-stats");
                LOGGER.warn("promotion traffic spike scenario={} sequence={} qps_multiplier=6.8 stock_reservation_success=91.2% "
                                + "payment_callback_lag_p95=18s affected_channels=[web,miniapp] "
                                + "suggestion=\"scale payment callback consumers and verify inventory lock TTL\"",
                        scenario, sequence);
            }
            default -> {
                long id = callInsert(actions, sequence, "checkout-order", "CREATED");
                callDetail(actions, id, "checkout-detail");
                callUpdateStatus(actions, id, "PAID", "checkout-paid");
                callList(actions, "checkout-paid-list", "PAID", "customer-" + (sequence % 5), null);
                LOGGER.info("checkout flow completed scenario={} sequence={} order_id={} payment_status=PAID "
                                + "inventory_lock=confirmed customer_segment=returning suggestion=\"watch duplicate payment callbacks\"",
                        scenario, sequence, id);
            }
        }
        LOGGER.info("gateway scenario completed scenario={} sequence={} action_count={} downstream_services=[test-insert,test-query]",
                scenario, sequence, actions.size());
        return Map.of(
                "service", "test-gateway",
                "scenario", scenario,
                "sequence", sequence,
                "actions", actions,
                "finishedAt", Instant.now().toString());
    }

    private void logScenarioStart(String scenario, long sequence) {
        LOGGER.info("gateway scenario started scenario={} sequence={} traffic_source=scheduled-gateway "
                        + "business_domain=order-fulfillment expected_downstream=[test-insert,test-query]",
                scenario, sequence);
    }

    private long callInsert(List<String> actions, long sequenceId, String action, String status) {
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-insert " + action)) {
            Map<String, Object> body = Map.of(
                    "orderNo", "ORD-" + sequenceId + "-" + action + "-" + System.nanoTime(),
                    "customerId", "customer-" + (sequenceId % 5),
                    "status", status,
                    "amount", 99 + (sequenceId % 100),
                    "message", action + " order event " + sequenceId,
                    "source", "test-gateway/" + action,
                    "sentAt", Instant.now().toString());
            Map<?, ?> response = restClient.post()
                    .uri(properties.insertUrl())
                    .body(body)
                    .retrieve()
                    .body(Map.class);
            actions.add("insert:" + action + ":" + response);
            Object id = response == null ? null : response.get("id");
            return id instanceof Number number ? number.longValue() : -1L;
        }
    }

    private void callDetail(List<String> actions, long id, String action) {
        if (id <= 0) {
            actions.add("detail:" + action + ":skipped");
            return;
        }
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-query " + action)) {
            String response = restClient.get()
                    .uri(properties.queryUrl() + "/" + id)
                    .retrieve()
                    .body(String.class);
            actions.add("detail:" + action + ":" + response);
        }
    }

    private void callList(List<String> actions, String action, String status, String customerId, String source) {
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-query " + action)) {
            StringBuilder uri = new StringBuilder(properties.queryUrl()).append("?limit=8");
            if (status != null) {
                uri.append("&status=").append(status);
            }
            if (customerId != null) {
                uri.append("&customerId=").append(customerId);
            }
            if (source != null) {
                uri.append("&source=").append(source);
            }
            String response = restClient.get()
                    .uri(uri.toString())
                    .retrieve()
                    .body(String.class);
            actions.add("list:" + action + ":" + response);
        }
    }

    private void callSearch(List<String> actions, String action, String keyword) {
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-query " + action)) {
            String response = restClient.get()
                    .uri(properties.queryUrl() + "/search?keyword=" + keyword + "&minutes=60&limit=8")
                    .retrieve()
                    .body(String.class);
            actions.add("search:" + action + ":" + response);
        }
    }

    private void callStats(List<String> actions, String action) {
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-query " + action)) {
            String response = restClient.get()
                    .uri(properties.queryUrl() + "/stats?sourcePrefix=test-gateway")
                    .retrieve()
                    .body(String.class);
            actions.add("stats:" + action + ":" + response);
        }
    }

    private void callUpdateStatus(List<String> actions, long id, String status, String action) {
        if (id <= 0) {
            actions.add("update:" + action + ":skipped");
            return;
        }
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-insert " + action)) {
            Map<String, Object> body = Map.of(
                    "status", status,
                    "message", action + " order " + id,
                    "source", "test-gateway/" + action);
            String response = restClient.put()
                    .uri(properties.insertUrl().replace("/insert", "/orders") + "/" + id + "/status")
                    .body(body)
                    .retrieve()
                    .body(String.class);
            actions.add("update:" + action + ":" + response);
        }
    }

    private void callDelete(List<String> actions, long id, String action) {
        if (id <= 0) {
            actions.add("delete:" + action + ":skipped");
            return;
        }
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-insert " + action)) {
            String response = restClient.delete()
                    .uri(properties.insertUrl().replace("/insert", "/orders") + "/" + id)
                    .retrieve()
                    .body(String.class);
            actions.add("delete:" + action + ":" + response);
        }
    }

    private void callQueryHealth(List<String> actions) {
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-query health")) {
            String response = restClient.get()
                    .uri(properties.queryHealthUrl())
                    .retrieve()
                    .body(String.class);
            actions.add("health:test-query:" + response);
        }
    }
}
