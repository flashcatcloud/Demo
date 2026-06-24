package com.example.insert;

import java.time.Duration;
import java.util.Map;

final class OperationLog {
    private static final org.slf4j.Logger LOGGER = org.slf4j.LoggerFactory.getLogger(OperationLog.class);
    private static final ThreadLocal<Span> CURRENT = new ThreadLocal<>();

    private OperationLog() {
    }

    static Span startServerSpan(String name) {
        Span span = new Span(name, System.nanoTime(), CURRENT.get());
        CURRENT.set(span);
        log("start", span, Map.of("kind", "server"));
        return span;
    }

    static Span startSpan(String name) {
        Span span = new Span(name, System.nanoTime(), CURRENT.get());
        CURRENT.set(span);
        log("start", span, Map.of("kind", "internal"));
        return span;
    }

    private static void finish(Span span, Throwable error) {
        Duration duration = Duration.ofNanos(System.nanoTime() - span.startedAtNanos());
        if (error == null) {
            log("end", span, Map.of("duration_ms", String.valueOf(duration.toMillis())));
        } else {
            log("error", span, Map.of(
                    "duration_ms", String.valueOf(duration.toMillis()),
                    "error", error.getClass().getSimpleName(),
                    "message", String.valueOf(error.getMessage())));
        }
        CURRENT.set(span.previous());
    }

    private static void log(String event, Span span, Map<String, String> attributes) {
        StringBuilder builder = new StringBuilder()
                .append("operation.").append(event)
                .append(" name=\"").append(span.name()).append('"');
        attributes.forEach((key, value) -> builder.append(' ').append(key).append('=').append(value));
        LOGGER.debug("{}", builder);
    }

    record Span(String name, long startedAtNanos, Span previous) implements AutoCloseable {
        @Override
        public void close() {
            OperationLog.finish(this, null);
        }

        void close(Throwable error) {
            OperationLog.finish(this, error);
        }
    }
}
