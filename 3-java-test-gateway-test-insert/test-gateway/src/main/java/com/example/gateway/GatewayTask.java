package com.example.gateway;

import java.util.concurrent.atomic.AtomicLong;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
class GatewayTask {
    private static final org.slf4j.Logger LOGGER = org.slf4j.LoggerFactory.getLogger(GatewayTask.class);
    private final RestClient restClient;
    private final GatewayProperties properties;
    private final AtomicLong sequence = new AtomicLong();
    private static final String[] SCENARIOS = {"checkout", "browse", "audit", "campaign"};

    GatewayTask(RestClient restClient, GatewayProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    @Scheduled(fixedDelayString = "${sample.fixed-delay}")
    void callDownstreamServices() {
        OperationLog.Span tick = OperationLog.startSpan("gateway.scheduled.tick");
        try {
            long id = sequence.incrementAndGet();
            callGatewayFlow(id, SCENARIOS[(int) (id % SCENARIOS.length)]);
        } catch (RuntimeException error) {
            tick.close(error);
            throw error;
        }
        tick.close();
    }

    private void callGatewayFlow(long sequenceId, String scenario) {
        try (OperationLog.Span ignored = OperationLog.startSpan("http.client test-gateway flow")) {
            String response = restClient.get()
                    .uri(properties.gatewayFlowUrl() + "?scenario=" + scenario + "&sequence=" + sequenceId
                            + "&source=scheduled-gateway")
                    .retrieve()
                    .body(String.class);
            LOGGER.info("scheduled gateway flow finished sequence={} scenario={} response_bytes={} next_delay_ms={}",
                    sequenceId, scenario, response == null ? 0 : response.length(), properties.fixedDelay());
        }
    }
}
