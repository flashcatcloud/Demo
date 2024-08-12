package main

import (
	"context"
	"errors"
	"fmt"
	"github.com/flashcatcloud/Demo/go-otel/pkg/trace"
	"log"
	"net/http"
	"os"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
)

func handleErr(err error, message string) {
	if err != nil {
		log.Fatalf("%s: %v", message, err)
	}
}

func main() {
	ctx := context.Background()
	shutdown, err := trace.SetupOTelSDK(ctx)
	handleErr(err, "failed to setup OTelSDK")
	defer func() {
		err = errors.Join(err, shutdown(ctx))
	}()

	tracer := otel.Tracer("demo-client-tracer")

	for {
		startTime := time.Now()
		ctx, span := tracer.Start(ctx, "ExecuteRequest")
		makeRequest(ctx)
		span.End()
		latencyMs := float64(time.Since(startTime)) / 1e6

		fmt.Printf("Latency: %.3fms\n", latencyMs)
		time.Sleep(time.Duration(10) * time.Second)
	}
}

func makeRequest(ctx context.Context) {

	demoServerAddr, ok := os.LookupEnv("DEMO_SERVER_ENDPOINT")
	if !ok {
		demoServerAddr = "http://localhost:8080/roll"
	}

	// Trace an HTTP client by wrapping the transport
	client := http.Client{
		Transport: otelhttp.NewTransport(http.DefaultTransport),
	}

	// Make sure we pass the context to the request to avoid broken traces.
	req, err := http.NewRequestWithContext(ctx, "GET", demoServerAddr, nil)
	if err != nil {
		handleErr(err, "failed to http request")
	}

	// All requests made with this client will create spans.
	res, err := client.Do(req)
	if err != nil {
		panic(err)
	}
	res.Body.Close()
}
