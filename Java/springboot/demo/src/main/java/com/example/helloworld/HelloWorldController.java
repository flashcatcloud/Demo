package com.example.helloworld;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestOperations;
import org.springframework.web.client.RestTemplate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestController
public class HelloWorldController {
    // 创建 Logger 实例
    private static final Logger logger = LoggerFactory.getLogger(HelloWorldController.class);


    OpenTelemetry openTelemetry = GlobalOpenTelemetry.get();
    Tracer tracer = openTelemetry.getTracer("demo-tracer");

    @Autowired
    private RestTemplate restTemplate;

    @GetMapping("/hello")
    public String hello() {
        // Start a new span named "helloSpan"
        Span span = tracer.spanBuilder("helloSpan").startSpan();
        try (Scope scope = span.makeCurrent()) {
            // Perform the work inside the span's scope
            span.addEvent("This is in hello span");
            logger.info("This is a log message with traceId");
            return echo("Hello World");
        } finally {
            // End the span when the work is done
            span.end();
        }
    }

    public String echo(String message) {
        // Start another span named "echoSpan"
        Span span = tracer.spanBuilder("echoSpan").startSpan();
        try (Scope scope = span.makeCurrent()) {
            span.addEvent("This is in echo span");
            // 调用另一个 API
            String response = restTemplate.getForObject("http://127.0.0.1:8080/test", String.class);

            // 返回结果
            return "Hello, World! Response from /test: " + response;
        } finally {
            span.end();
        }
    }

    @GetMapping("/test")
    public String ping() {
        return "Test";
    }
}

