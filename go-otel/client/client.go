package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	gotrace "go.opentelemetry.io/otel/trace"

	pkgotel "github.com/flashcatcloud/Demo/go-otel/pkg/otel"
)

// Client 客户端结构体
type Client struct {
	httpClient   *http.Client
	serverURL    string
	tracer       gotrace.Tracer
	createdUsers []User // 跟踪创建的用户
	names        []string
}

func NewClient() *Client {
	// 获取服务器地址
	serverURL := os.Getenv("DEMO_SERVER_ENDPOINT")
	if serverURL == "" {
		port := os.Getenv("GO_DEMO_SERVER_PORT")
		if port == "" {
			port = "8080"
		}
		serverURL = fmt.Sprintf("http://localhost:%s", port)
	}

	// 移除末尾的路径，保留基础URL
	if strings.HasSuffix(serverURL, "/roll") {
		serverURL = strings.TrimSuffix(serverURL, "/roll")
	}

	return &Client{
		httpClient: &http.Client{
			Transport: otelhttp.NewTransport(http.DefaultTransport),
			Timeout:   30 * time.Second,
		},
		serverURL:    serverURL,
		tracer:       otel.Tracer("demo-client"),
		createdUsers: make([]User, 0),
		names:        commonNames,
	}
}

func main() {
	ctx := context.Background()

	// 设置OpenTelemetry
	shutdown, err := pkgotel.SetupOTelSDK(ctx)
	handleErr(err, "设置OpenTelemetry失败")
	defer func() {
		err = errors.Join(err, shutdown(ctx))
	}()

	// 创建客户端
	client := NewClient()

	log.Printf("客户端启动，服务器地址: %s", client.serverURL)

	// 创建可取消的context
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// 启动Roll请求协程
	go client.runRollRequests(ctx)

	// 启动用户请求协程
	go client.runUserRequests(ctx)

	// 主线程保持运行
	select {}
}
