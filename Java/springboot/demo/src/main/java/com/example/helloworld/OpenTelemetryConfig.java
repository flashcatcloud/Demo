package com.example.helloworld;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanBuilder;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.SimpleSpanProcessor;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenTelemetryConfig {

//    @Bean
//    public OpenTelemetry openTelemetry() {
//        OtlpGrpcSpanExporter spanExporter = OtlpGrpcSpanExporter.builder()
//                .setEndpoint("http://10.201.0.210:4317")  // 替换为你的OTLP接收器的地址
//                .build();
//
//        SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
//                .addSpanProcessor(SimpleSpanProcessor.create(spanExporter))
//                .build();
//
//        return OpenTelemetrySdk.builder()
//                .setTracerProvider(tracerProvider)
//                .buildAndRegisterGlobal();
//    }
//
//    @Bean
//    public Tracer tracer(OpenTelemetry openTelemetry) {
//        return openTelemetry.getTracer("com.example.helloworld");
//    }
}
