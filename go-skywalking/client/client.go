package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/apache/skywalking-go"
)

func handleErr(err error, message string) {
	if err != nil {
		log.Fatalf("%s: %v", message, err)
	}
}

func main() {
	ctx := context.Background()

	for {
		startTime := time.Now()
		makeRequest(ctx)
		latencyMs := float64(time.Since(startTime)) / 1e6

		fmt.Printf("Latency: %.3fms\n", latencyMs)
		time.Sleep(time.Duration(30) * time.Second)
	}
}

func makeRequest(ctx context.Context) {

	demoServerAddr, ok := os.LookupEnv("DEMO_SERVER_ENDPOINT")
	if !ok {
		demoServerAddr = fmt.Sprintf("http://localhost:%s/roll", os.Getenv("GO_DEMO_SERVER_PORT"))
	}

	// Trace an HTTP client by wrapping the transport
	client := http.Client{
		Transport: http.DefaultTransport,
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
	_ = res.Body.Close()
}
