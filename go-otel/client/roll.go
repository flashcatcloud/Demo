package main

import (
	"log"
	"time"
	"context"
	"net/http"
	"fmt"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
)

func (c *Client) runRollRequests(ctx context.Context) {
	log.Println("开始发送Roll请求，每0.5秒一次...")

	for {
		select {
		case <-ctx.Done():
			return
		default:
			if err := c.makeRollRequest(ctx); err != nil {
				log.Printf("Roll请求失败: %v", err)
			}
			time.Sleep(500 * time.Millisecond)
		}
	}
}

func (c *Client) makeRollRequest(ctx context.Context) error {
	ctx, span := c.tracer.Start(ctx, "client.rollRequest")
	defer span.End()

	url := c.serverURL + "/roll"
	span.SetAttributes(
		attribute.String("http.url", url),
		attribute.String("http.method", "GET"),
	)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		span.SetStatus(codes.Error, "failed to create request")
		span.RecordError(err)
		return fmt.Errorf("创建roll请求失败: %w", err)
	}

	startTime := time.Now()
	resp, err := c.httpClient.Do(req)
	if err != nil {
		span.SetStatus(codes.Error, "request failed")
		span.RecordError(err)
		return fmt.Errorf("roll请求失败: %w", err)
	}
	defer resp.Body.Close()

	duration := time.Since(startTime)
	span.SetAttributes(
		attribute.Int("http.status_code", resp.StatusCode),
		attribute.Float64("http.duration_ms", float64(duration.Nanoseconds())/1e6),
	)

	if resp.StatusCode != http.StatusOK {
		span.SetStatus(codes.Error, "non-200 status code")
		return fmt.Errorf("roll请求返回状态码: %d", resp.StatusCode)
	}

	log.Printf("Roll请求成功 - 状态码: %d, 耗时: %.3fms", resp.StatusCode, float64(duration.Nanoseconds())/1e6)
	return nil
}
