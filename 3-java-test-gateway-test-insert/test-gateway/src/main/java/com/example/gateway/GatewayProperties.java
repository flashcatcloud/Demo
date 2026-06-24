package com.example.gateway;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "sample")
public record GatewayProperties(String insertUrl, String queryUrl, String queryHealthUrl, String gatewayFlowUrl,
                                long fixedDelay) {
}
