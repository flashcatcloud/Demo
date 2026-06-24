package com.example.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableScheduling
@SpringBootApplication
public class TestGatewayApplication {
    public static void main(String[] args) {
        SpringApplication.run(TestGatewayApplication.class, args);
    }
}
