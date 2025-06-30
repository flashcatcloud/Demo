package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	"runtime"

	"github.com/gin-gonic/gin"
	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	dto "github.com/prometheus/client_model/go"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"

	"github.com/flashcatcloud/Demo/go-otel/pkg/otel"
)

const (
	serviceName = "go-demo-mcp-server"
)

var (
	// 从环境变量获取端口配置，如果未设置则使用默认值
	mcpPort     = getEnvWithDefault("MCP_SSE_PORT", ":8184") // MCP SSE服务端口
	metricsPort = getEnvWithDefault("METRICS_PORT", ":8185") // Prometheus指标端口

	tracer = otel.Tracer(serviceName)

	// Prometheus metrics
	connectedClients = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "mcp_connected_clients",
		Help: "Number of connected MCP clients",
	})

	toolCallsTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "mcp_tool_calls_total",
		Help: "Total number of tool calls",
	}, []string{"tool_name", "status"})

	toolCallDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "mcp_tool_call_duration_seconds",
		Help: "Duration of tool calls",
	}, []string{"tool_name"})
)

// getEnvWithDefault 获取环境变量，如果不存在则返回默认值
func getEnvWithDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func init() {
	// Register Prometheus metrics
	prometheus.MustRegister(connectedClients)
	prometheus.MustRegister(toolCallsTotal)
	prometheus.MustRegister(toolCallDuration)
}

func main() {
	// 打印端口配置信息
	log.Printf("服务配置:")
	log.Printf("  - MCP SSE服务端口: %s (环境变量: MCP_SSE_PORT)", mcpPort)
	log.Printf("  - Metrics监控端口: %s (环境变量: METRICS_PORT)", metricsPort)
	log.Printf("端口说明:")
	log.Printf("  - MCP SSE端口: 用于MCP协议通信和工具调用")
	log.Printf("  - Metrics端口: 用于Prometheus指标、健康检查和状态监控")

	// 平滑处理 SIGINT (CTRL+C)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// 设置 OpenTelemetry
	otelShutdown, err := otel.SetupOTelSDK(ctx)
	if err != nil {
		log.Fatalf("Failed to setup OpenTelemetry: %v", err)
	}
	// 妥善处理停机，确保无泄漏
	defer func() {
		err = errors.Join(err, otelShutdown(ctx))
	}()

	// Create MCP server
	s := server.NewMCPServer(serviceName, "0.0.1")

	// Add tools
	setupTools(s)

	// Start metrics server in a goroutine
	go startMetricsServer()

	// Create SSE server using mark3labs/mcp-go
	log.Printf("Starting MCP SSE server on %s", mcpPort)
	sseServer := server.NewSSEServer(s,
		server.WithBaseURL("http://localhost"+mcpPort),
		server.WithSSEEndpoint("/sse"),
		server.WithMessageEndpoint("/message"),
		server.WithSSEContextFunc(func(ctx context.Context, r *http.Request) context.Context {
			// Add tracing context
			_, span := tracer.Start(ctx, "mcp.sse.connection")
			defer span.End()

			// Update metrics
			connectedClients.Inc()

			span.SetAttributes(
				attribute.String("transport", "sse"),
				attribute.String("endpoint", "/sse"),
			)
			return ctx
		}),
	)

	// Start SSE server
	sseErr := make(chan error, 1)
	go func() {
		sseErr <- sseServer.Start(mcpPort)
	}()

	// Wait for interruption
	select {
	case err = <-sseErr:
		// Error when starting SSE server
		if err != nil && err != http.ErrServerClosed {
			log.Printf("SSE server error: %v", err)
		}
	case <-ctx.Done():
		// Wait for first CTRL+C
		stop()
		log.Println("Shutting down SSE server...")

		// Gracefully shutdown SSE server
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := sseServer.Shutdown(shutdownCtx); err != nil {
			log.Printf("SSE server forced to shutdown: %v", err)
		}
	}

	log.Println("MCP server exiting")
}

func setupTools(s *server.MCPServer) {
	// Echo tool
	echoTool := mcp.NewTool("echo",
		mcp.WithDescription("Echo back the input message"),
		mcp.WithString("message",
			mcp.Required(),
			mcp.Description("Message to echo back"),
		),
	)
	s.AddTool(echoTool, handleEcho)

	// Calculator tool
	calculatorTool := mcp.NewTool("calculator",
		mcp.WithDescription("Perform basic arithmetic operations"),
		mcp.WithString("operation",
			mcp.Required(),
			mcp.Description("The operation to perform (add, subtract, multiply, divide)"),
			mcp.Enum("add", "subtract", "multiply", "divide"),
		),
		mcp.WithNumber("x",
			mcp.Required(),
			mcp.Description("First number"),
		),
		mcp.WithNumber("y",
			mcp.Required(),
			mcp.Description("Second number"),
		),
	)
	s.AddTool(calculatorTool, handleCalculator)

	// Current time tool
	currentTimeTool := mcp.NewTool("current_time",
		mcp.WithDescription("Get the current system time"),
	)
	s.AddTool(currentTimeTool, handleCurrentTime)

	// System info tool
	systemInfoTool := mcp.NewTool("system_info",
		mcp.WithDescription("Get basic system information"),
	)
	s.AddTool(systemInfoTool, handleSystemInfo)

	log.Println("MCP tools registered successfully")
}

func handleEcho(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	_, span := tracer.Start(ctx, "mcp.tool.echo")
	defer span.End()

	timer := prometheus.NewTimer(toolCallDuration.WithLabelValues("echo"))
	defer timer.ObserveDuration()

	// Extract the message from arguments
	message, err := request.RequireString("message")
	if err != nil {
		toolCallsTotal.WithLabelValues("echo", "error").Inc()
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return mcp.NewToolResultError(err.Error()), nil
	}

	span.SetAttributes(
		attribute.String("tool.name", "echo"),
		attribute.String("tool.message", message),
	)

	result := "Echo: " + message

	toolCallsTotal.WithLabelValues("echo", "success").Inc()
	span.SetAttributes(attribute.String("tool.result", result))

	return mcp.NewToolResultText(result), nil
}

func handleCalculator(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	_, span := tracer.Start(ctx, "mcp.tool.calculator")
	defer span.End()

	timer := prometheus.NewTimer(toolCallDuration.WithLabelValues("calculator"))
	defer timer.ObserveDuration()

	// Extract arguments
	operation, err := request.RequireString("operation")
	if err != nil {
		toolCallsTotal.WithLabelValues("calculator", "error").Inc()
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return mcp.NewToolResultError(err.Error()), nil
	}

	x, err := request.RequireFloat("x")
	if err != nil {
		toolCallsTotal.WithLabelValues("calculator", "error").Inc()
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return mcp.NewToolResultError(err.Error()), nil
	}

	y, err := request.RequireFloat("y")
	if err != nil {
		toolCallsTotal.WithLabelValues("calculator", "error").Inc()
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return mcp.NewToolResultError(err.Error()), nil
	}

	span.SetAttributes(
		attribute.String("tool.name", "calculator"),
		attribute.String("tool.operation", operation),
		attribute.Float64("tool.x", x),
		attribute.Float64("tool.y", y),
	)

	var result float64
	switch operation {
	case "add":
		result = x + y
	case "subtract":
		result = x - y
	case "multiply":
		result = x * y
	case "divide":
		if y == 0 {
			err := errors.New("division by zero")
			toolCallsTotal.WithLabelValues("calculator", "error").Inc()
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())
			return mcp.NewToolResultError("cannot divide by zero"), nil
		}
		result = x / y
	default:
		err := errors.New("invalid operation")
		toolCallsTotal.WithLabelValues("calculator", "error").Inc()
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return mcp.NewToolResultError("invalid operation"), nil
	}

	toolCallsTotal.WithLabelValues("calculator", "success").Inc()
	span.SetAttributes(attribute.Float64("tool.result", result))

	return mcp.NewToolResultText(fmt.Sprintf("%.2f", result)), nil
}

func handleCurrentTime(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	_, span := tracer.Start(ctx, "mcp.tool.current_time")
	defer span.End()

	timer := prometheus.NewTimer(toolCallDuration.WithLabelValues("current_time"))
	defer timer.ObserveDuration()

	currentTime := time.Now().Format(time.RFC3339)

	span.SetAttributes(
		attribute.String("tool.name", "current_time"),
		attribute.String("tool.result", currentTime),
	)

	toolCallsTotal.WithLabelValues("current_time", "success").Inc()

	return mcp.NewToolResultText(currentTime), nil
}

func handleSystemInfo(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	_, span := tracer.Start(ctx, "mcp.tool.system_info")
	defer span.End()

	timer := prometheus.NewTimer(toolCallDuration.WithLabelValues("system_info"))
	defer timer.ObserveDuration()

	info := map[string]interface{}{
		"go_version": runtime.Version(),
		"os":         runtime.GOOS,
		"arch":       runtime.GOARCH,
		"num_cpu":    runtime.NumCPU(),
		"timestamp":  time.Now().Unix(),
	}

	span.SetAttributes(
		attribute.String("tool.name", "system_info"),
		attribute.String("system.os", runtime.GOOS),
		attribute.String("system.arch", runtime.GOARCH),
		attribute.Int("system.cpu", runtime.NumCPU()),
	)

	toolCallsTotal.WithLabelValues("system_info", "success").Inc()

	// Convert map to JSON-like string for display
	result := fmt.Sprintf("System Info:\n- OS: %s\n- Arch: %s\n- CPUs: %d\n- Go Version: %s\n- Timestamp: %d",
		info["os"], info["arch"], info["num_cpu"], info["go_version"], info["timestamp"])

	return mcp.NewToolResultText(result), nil
}

func startMetricsServer() {
	r := gin.New()
	r.Use(gin.Logger())
	r.Use(gin.Recovery())
	r.Use(otelgin.Middleware(serviceName))

	// Prometheus metrics endpoint
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		_, span := tracer.Start(c.Request.Context(), "metrics.health_check")
		defer span.End()

		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": serviceName,
			"version": "0.0.1",
		})
	})

	// Status endpoint with metrics
	r.GET("/status", func(c *gin.Context) {
		_, span := tracer.Start(c.Request.Context(), "metrics.status")
		defer span.End()

		// Get connected clients metric
		connectedClientsValue := 0.0
		metric := &dto.Metric{}
		if err := connectedClients.Write(metric); err == nil {
			connectedClientsValue = metric.GetGauge().GetValue()
		}

		c.JSON(http.StatusOK, gin.H{
			"server":            serviceName,
			"version":           "0.0.1",
			"connected_clients": connectedClientsValue,
			"transport":         "sse",
			"endpoint":          "http://localhost" + mcpPort + "/sse",
		})
	})

	log.Printf("Starting metrics server on %s", metricsPort)
	if err := http.ListenAndServe(metricsPort, r); err != nil {
		log.Printf("Metrics server error: %v", err)
	}
}
