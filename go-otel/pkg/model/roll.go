package model

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	gotrace "go.opentelemetry.io/otel/trace"

	logx "github.com/flashcatcloud/Demo/go-otel/pkg/log"
	"github.com/flashcatcloud/Demo/go-otel/pkg/mcp"
	"github.com/flashcatcloud/Demo/go-otel/pkg/redis"
	"github.com/prometheus/client_golang/prometheus"
)

var (
	// 初始化
	opsProcessed = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "myapp_processed_ops_total",
		Help: "The total number of processed events",
	})
)

func RecordMetrics() {
	// 注册opsProcessed
	if err := prometheus.Register(opsProcessed); err != nil {
		fmt.Println(err)
	} else {
		fmt.Println("taskCounter registered.")
	}
	go func() {
		for {
			opsProcessed.Inc()
			time.Sleep(2 * time.Second)
		}
	}()
}

func Roll(c *gin.Context) {

	number, err := rollOnce(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, err.Error())
		return
	}

	opsProcessed.Inc()
	// 摇骰子次数的指标 +1
	// rollCnt.Add(ctx, 1, metric.WithAttributes(rollValueAttr))

	c.JSON(http.StatusOK, gin.H{"msg": number})
}

func rollOnce(ctx context.Context) (int, error) {
	ctx, span := otel.Tracer("roll").Start(ctx, "rollOnce") // 开始 span
	defer span.End()
	span.SetAttributes(attribute.String("function", "rollOnce"))

	var (
		err    error
		number int
	)

	// 生成两个随机数（1-6范围，模拟骰子）
	dice1 := 1 + rand.Intn(6)
	dice2 := 1 + rand.Intn(6)

	span.SetAttributes(
		attribute.Int("dice1", dice1),
		attribute.Int("dice2", dice2),
	)

	log.Printf("生成随机数: dice1=%d, dice2=%d", dice1, dice2)

	// 调用MCP服务器进行计算
	result, err := mcp.CallCalculatorTool(ctx, "add", float64(dice1), float64(dice2))
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "MCP计算失败")
		log.Printf("MCP计算失败，使用本地计算: %v", err)
		// 如果MCP调用失败，使用本地计算作为回退
		number = dice1 + dice2
	} else {
		number = int(result)
	}

	span.SetAttributes(attribute.Int("final_number", number))

	if err = redis.DoSomething(ctx, redis.Rdb); err != nil {
		span.SetStatus(codes.Error, err.Error())
		// 记录错误详情
		span.RecordError(err, gotrace.WithStackTrace(true))
		log.Printf("doSomething failed:%v\n!", err)
		return number, err
	}

	logx.Logger.InfoContext(ctx, fmt.Sprintf("rollOnce number:%d (通过MCP计算: %d + %d)", number, dice1, dice2))

	return number, nil
}
