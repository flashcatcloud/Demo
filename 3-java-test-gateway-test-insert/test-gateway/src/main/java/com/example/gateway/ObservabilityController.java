package com.example.gateway;

import java.time.Instant;
import java.util.Map;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping
class ObservabilityController {
    @GetMapping("/api/health")
    Map<String, Object> health() {
        return Map.of(
                "service", "test-gateway",
                "status", "UP",
                "host", "sample-host-gateway",
                "role", "scheduler",
                "checkedAt", Instant.now().toString());
    }

    @GetMapping(value = "/mock/metrics", produces = MediaType.TEXT_PLAIN_VALUE)
    String metrics() {
        return """
                # HELP mock_service_up Whether the mock service is healthy.
                # TYPE mock_service_up gauge
                mock_service_up{service="test-gateway",host="sample-host-gateway"} 1
                # HELP mock_scheduler_tick_total Mock scheduler ticks for demo topology.
                # TYPE mock_scheduler_tick_total counter
                mock_scheduler_tick_total{service="test-gateway"} 1
                # HELP mock_downstream_dependency_total Downstream dependencies in the sample.
                # TYPE mock_downstream_dependency_total gauge
                mock_downstream_dependency_total{service="test-gateway"} 2
                """;
    }
}
