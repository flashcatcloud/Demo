package otel

import (
	"log"
	"os"
	"time"

	"context"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.15.0"
	"github.com/google/uuid"
)

const (
	SERVICE_NAME       = "go-otel-demo-server"
	SERVICE_VERSION    = "v0.0.1"
	DEPLOY_ENVIRONMENT = "test"
	HTTP_ENDPOINT      = "tracing-analysis-dc-bj.aliyuncs.com"
	HTTP_URL_PATH      = "adapt_ankqafli5s@888a5b759486b30_ankqafli5s@53df7ad2afe8301/api/otlp/traces"
)

// 设置应用资源
func newResource(ctx context.Context) *resource.Resource {
	hostName, _ := os.Hostname()

	r, err := resource.New(
		ctx,
		resource.WithFromEnv(),
		resource.WithProcess(),
		resource.WithTelemetrySDK(),
		resource.WithHost(),
		resource.WithAttributes(
			semconv.ServiceNameKey.String(SERVICE_NAME),                 // 应用名
			semconv.ServiceVersionKey.String(SERVICE_VERSION),           // 应用版本
			semconv.DeploymentEnvironmentKey.String(DEPLOY_ENVIRONMENT), // 部署环境
			semconv.HostNameKey.String(hostName),                        // 主机名
			semconv.ServiceInstanceIDKey.String(uuid.NewString()),       // instance.id
		),
	)

	if err != nil {
		log.Fatalf("%s: %v", "Failed to create OpenTelemetry resource", err)
	}
	return r
}

func newHTTPExporterAndSpanProcessor(ctx context.Context) (*otlptrace.Exporter, sdktrace.SpanProcessor) {

	traceExporter, err := otlptrace.New(ctx, otlptracehttp.NewClient(
		otlptracehttp.WithEndpoint(HTTP_ENDPOINT),
		otlptracehttp.WithURLPath(HTTP_URL_PATH),
		otlptracehttp.WithInsecure(),
		otlptracehttp.WithCompression(1)))

	if err != nil {
		log.Fatalf("%s: %v", "Failed to create the OpenTelemetry trace exporter", err)
	}

	batchSpanProcessor := sdktrace.NewBatchSpanProcessor(traceExporter)

	return traceExporter, batchSpanProcessor
}

// InitOpenTelemetry OpenTelemetry 初始化方法
func InitOpenTelemetry() func() {
	ctx := context.Background()

	var traceExporter *otlptrace.Exporter
	var batchSpanProcessor sdktrace.SpanProcessor

	traceExporter, batchSpanProcessor = newHTTPExporterAndSpanProcessor(ctx)

	otelResource := newResource(ctx)

	traceProvider := sdktrace.NewTracerProvider(
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
		sdktrace.WithResource(otelResource),
		sdktrace.WithSpanProcessor(batchSpanProcessor))

	otel.SetTracerProvider(traceProvider)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))

	return func() {
		cxt, cancel := context.WithTimeout(ctx, time.Second)
		defer cancel()
		if err := traceExporter.Shutdown(cxt); err != nil {
			otel.Handle(err)
		}
	}
}
