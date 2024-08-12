package com.example.helloworld;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;


@RestController
public class HelloWorldController {
//
//    private final Tracer tracer;
//
//    public HelloWorldController(Tracer tracer) {
//        this.tracer = tracer;
//    }
    OpenTelemetry openTelemetry = GlobalOpenTelemetry.get();
    Tracer tracer = openTelemetry.getTracer("demo-tracer");


    @GetMapping("/hello")
    public String hello() {
        // Start a new span named "helloSpan"
        Span span = tracer.spanBuilder("helloSpan").startSpan();
        try (Scope scope = span.makeCurrent()) {
            // Perform the work inside the span's scope
            span.addEvent("This is in hello span");
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
            return message;
        } finally {
            span.end();
        }
    }

    @GetMapping("/ping")
    public String ping() {
        // Start a new span named "helloSpan"
        Span span = tracer.spanBuilder("helloSpan").startSpan();
        try (Scope scope = span.makeCurrent()) {
            // Perform the work inside the span's scope
            span.addEvent("This is in hello span");
            return echo("Hello World");
        } finally {
            // End the span when the work is done
            span.end();
        }
    }
}

