package com.example.insert;

import java.time.Instant;
import java.util.Map;

import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping
class ObservabilityController {
    private final JdbcTemplate jdbcTemplate;

    ObservabilityController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @GetMapping("/api/health")
    Map<String, Object> health() {
        Integer total = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM orders", Integer.class);
        return Map.of(
                "service", "test-insert",
                "status", "UP",
                "host", "sample-host-a",
                "database", "mysql/order_fulfillment.orders",
                "records", total == null ? 0 : total,
                "checkedAt", Instant.now().toString());
    }

    @GetMapping(value = "/mock/metrics", produces = MediaType.TEXT_PLAIN_VALUE)
    String metrics() {
        Integer total = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM orders", Integer.class);
        return """
                # HELP mock_service_up Whether the mock service is healthy.
                # TYPE mock_service_up gauge
                mock_service_up{service="test-insert",host="sample-host-a"} 1
                # HELP mock_db_events_total Current event rows in the sample database.
                # TYPE mock_db_events_total gauge
                mock_db_events_total{service="test-insert",database="mysql/order_fulfillment.orders"} %d
                # HELP mock_http_server_requests_total Mock HTTP request count for demo topology.
                # TYPE mock_http_server_requests_total counter
                mock_http_server_requests_total{service="test-insert",api="/api/insert"} %d
                """.formatted(total == null ? 0 : total, total == null ? 0 : total);
    }
}
