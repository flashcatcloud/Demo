package com.example.query;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
class QueryController {
    private static final org.slf4j.Logger LOGGER = org.slf4j.LoggerFactory.getLogger(QueryController.class);
    private final JdbcTemplate jdbcTemplate;

    QueryController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @GetMapping("/query")
    Map<String, Object> query() {
        return list(null, null, null, 5);
    }

    @GetMapping("/orders/{id}")
    Map<String, Object> detail(@PathVariable("id") long id) {
        try (OperationLog.Span ignored = OperationLog.startSpan("db.select order by id")) {
            List<Map<String, Object>> rows = jdbcTemplate.queryForList("""
                    SELECT id, order_no, customer_id, status, amount, message, source, created_at, updated_at
                    FROM orders
                    WHERE id = ?
                    """, id);
            LOGGER.info("order detail queried order_id={} found={} query_pattern=point_lookup index=PRIMARY "
                            + "suggestion=\"point lookup should stay below 20ms p95\"",
                    id, !rows.isEmpty());
            return Map.of("found", !rows.isEmpty(), "order", rows.isEmpty() ? Map.of() : rows.get(0));
        }
    }

    @GetMapping("/orders")
    Map<String, Object> list(@RequestParam(name = "status", required = false) String status,
                             @RequestParam(name = "customerId", required = false) String customerId,
                             @RequestParam(name = "source", required = false) String source,
                             @RequestParam(name = "limit", defaultValue = "10") int limit) {
        try (OperationLog.Span ignored = OperationLog.startSpan("db.list orders")) {
            List<Object> args = new ArrayList<>();
            StringBuilder where = new StringBuilder("WHERE 1 = 1");
            if (status != null && !status.isBlank()) {
                where.append(" AND status = ?");
                args.add(status);
            }
            if (customerId != null && !customerId.isBlank()) {
                where.append(" AND customer_id = ?");
                args.add(customerId);
            }
            if (source != null && !source.isBlank()) {
                where.append(" AND source LIKE ?");
                args.add(source + "%");
            }
            Integer total = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM orders " + where, Integer.class,
                    args.toArray());
            args.add(Math.max(1, Math.min(limit, 50)));
            List<Map<String, Object>> latest = jdbcTemplate.queryForList("""
                    SELECT id, order_no, customer_id, status, amount, message, source, created_at, updated_at
                    FROM orders
                    %s
                    ORDER BY created_at DESC, id DESC
                    LIMIT ?
                    """.formatted(where), args.toArray());
            int totalValue = total == null ? 0 : total;
            LOGGER.info("order list queried status={} customer_id={} source={} total={} returned={} "
                            + "query_pattern=filtered_page index_hint=idx_orders_status_created_at",
                    valueOrAll(status), valueOrAll(customerId), valueOrAll(source), totalValue, latest.size());
            if (totalValue > 10000 && (customerId == null || customerId.isBlank())) {
                LOGGER.warn("wide order list query detected status={} total={} returned={} "
                                + "impact=\"dashboard may scan too many rows\" suggestion=\"add customerId or source filter for drilldown\"",
                        valueOrAll(status), totalValue, latest.size());
            }
            return Map.of("total", total == null ? 0 : total, "latest", latest);
        }
    }

    @GetMapping("/orders/search")
    Map<String, Object> search(@RequestParam(name = "keyword", defaultValue = "order") String keyword,
                               @RequestParam(name = "minutes", defaultValue = "30") int minutes,
                               @RequestParam(name = "limit", defaultValue = "10") int limit) {
        try (OperationLog.Span ignored = OperationLog.startSpan("db.search orders")) {
            List<Map<String, Object>> rows = jdbcTemplate.queryForList("""
                    SELECT id, order_no, customer_id, status, amount, message, source, created_at, updated_at
                    FROM orders
                    WHERE message LIKE ?
                      AND created_at >= DATE_SUB(NOW(), INTERVAL ? MINUTE)
                    ORDER BY created_at DESC, id DESC
                    LIMIT ?
                    """, "%" + keyword + "%", Math.max(1, minutes), Math.max(1, Math.min(limit, 50)));
            LOGGER.info("order keyword search keyword={} minutes={} returned={} query_pattern=time_window_like "
                            + "suggestion=\"keep search window narrow or route to search index\"",
                    keyword, Math.max(1, minutes), rows.size());
            if (rows.size() >= Math.max(1, Math.min(limit, 50))) {
                LOGGER.warn("keyword search hit limit keyword={} limit={} impact=\"result truncated\" "
                                + "suggestion=\"increase specificity or check message index coverage\"",
                        keyword, Math.max(1, Math.min(limit, 50)));
            }
            return Map.of("keyword", keyword, "matches", rows);
        }
    }

    @GetMapping("/orders/stats")
    Map<String, Object> stats(@RequestParam(name = "sourcePrefix", defaultValue = "test-gateway") String sourcePrefix) {
        try (OperationLog.Span ignored = OperationLog.startSpan("db.stats orders")) {
            List<Map<String, Object>> rows = jdbcTemplate.queryForList("""
                    SELECT status, COUNT(*) AS total, SUM(amount) AS amount_total
                    FROM orders
                    WHERE source LIKE ?
                    GROUP BY status
                    ORDER BY total DESC
                    """, sourcePrefix + "%");
            LOGGER.info("order status aggregation source_prefix={} groups={} query_pattern=group_by_status "
                            + "business_metric=fulfillment_distribution",
                    sourcePrefix, rows.size());
            if (!rows.isEmpty()) {
                LOGGER.warn("fulfillment distribution anomaly source_prefix={} top_status={} top_count={} "
                                + "impact=\"campaign or audit flow may dominate order mix\" suggestion=\"compare with 30m baseline before alerting\"",
                        sourcePrefix, rows.get(0).get("status"), rows.get(0).get("total"));
            }
            return Map.of("sourcePrefix", sourcePrefix, "stats", rows);
        }
    }

    private String valueOrAll(String value) {
        return value == null || value.isBlank() ? "ALL" : value;
    }
}
