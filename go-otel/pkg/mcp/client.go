// Package mcp 提供与 MCP 服务器交互的客户端工具。
package mcp

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/mark3labs/mcp-go/client"
	"github.com/mark3labs/mcp-go/mcp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
)

var (
	sharedMCPClient *client.Client
	mcpInitOnce     sync.Once
)

// getMCPServerURL 返回 MCP 服务器的 SSE 地址。
func getMCPServerURL() string {
	port := os.Getenv("MCP_SSE_PORT")
	if port == "" {
		port = "8184"
	}
	return fmt.Sprintf("http://localhost:%s", port)
}

// getSharedMCPClient 返回全局唯一的 MCP 客户端实例，必要时自动初始化。
func getSharedMCPClient() (*client.Client, error) {
	var err error
	mcpInitOnce.Do(func() {
		sharedMCPClient, err = client.NewSSEMCPClient(getMCPServerURL() + "/sse")
		if err != nil {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err = sharedMCPClient.Start(ctx); err != nil {
			sharedMCPClient = nil
			return
		}
		// Initialize
		initRequest := mcp.InitializeRequest{}
		initRequest.Params.ProtocolVersion = mcp.LATEST_PROTOCOL_VERSION
		initRequest.Params.ClientInfo = mcp.Implementation{
			Name:    "go-otel-demo-server",
			Version: "1.0.0",
		}
		_, err = sharedMCPClient.Initialize(ctx, initRequest)
		if err != nil {
			sharedMCPClient = nil
		}
	})
	return sharedMCPClient, err
}

// CallCalculatorTool 调用 MCP 服务器的 calculator 工具进行加法等计算。
// operation 支持 "add"、"sub"、"mul"、"div" 等。
// 返回计算结果或错误。
func CallCalculatorTool(ctx context.Context, operation string, x, y float64) (float64, error) {
	ctx, span := otel.Tracer("roll").Start(ctx, "CallCalculatorTool")
	defer span.End()

	span.SetAttributes(
		attribute.String("mcp.tool", "calculator"),
		attribute.String("mcp.operation", operation),
		attribute.Float64("mcp.x", x),
		attribute.Float64("mcp.y", y),
	)

	cli, err := getSharedMCPClient()
	if err != nil || cli == nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "failed to initialize MCP cli")
		return 0, fmt.Errorf("MCP 客户端初始化失败: %w", err)
	}

	toolReq := mcp.CallToolRequest{
		Params: mcp.CallToolParams{
			Name: "calculator",
			Arguments: map[string]interface{}{
				"operation": operation,
				"x":         x,
				"y":         y,
			},
		},
	}

	startTime := time.Now()
	result, err := cli.CallTool(ctx, toolReq)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "MCP tool call failed")
		return 0, fmt.Errorf("MCP 工具调用失败: %w", err)
	}
	duration := time.Since(startTime)
	span.SetAttributes(attribute.Float64("mcp.duration_ms", float64(duration.Nanoseconds())/1e6))

	if len(result.Content) == 0 {
		return 0, fmt.Errorf("MCP 响应内容为空")
	}

	var resultStr string
	if textContent, ok := mcp.AsTextContent(result.Content[0]); ok {
		resultStr = textContent.Text
	} else {
		resultStr = fmt.Sprintf("%v", result.Content[0])
	}

	if resultStr == "" {
		return 0, fmt.Errorf("未找到文本结果")
	}

	calculationResult, err := strconv.ParseFloat(resultStr, 64)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "parse result failed")
		return 0, fmt.Errorf("解析计算结果失败: %w", err)
	}

	span.SetAttributes(attribute.Float64("mcp.result", calculationResult))
	return calculationResult, nil
}

// CloseSharedMCPClient 关闭全局 MCP 客户端连接。
func CloseSharedMCPClient() error {
	if sharedMCPClient != nil {
		err := sharedMCPClient.Close()
		sharedMCPClient = nil
		return err
	}
	return nil
}
