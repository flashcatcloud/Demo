package model

import (
	"fmt"
	"log"
	"context"
	"net/http"
	"time"
	"math/rand"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	gotrace "go.opentelemetry.io/otel/trace"

	"github.com/flashcatcloud/Demo/go-otel/pkg/redis"
	logx "github.com/flashcatcloud/Demo/go-otel/pkg/log"
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
	number = 1 + rand.Intn(6)
	if err = redis.DoSomething(ctx, redis.Rdb); err != nil {
		span.SetStatus(codes.Error, err.Error())
		// 记录错误详情
		span.RecordError(err, gotrace.WithStackTrace(true))
		log.Printf("doSomething failed:%v\n!", err)
		return number, err
	}

	logx.Logger.InfoContext(ctx, fmt.Sprintf("rollOnce number:%d", number))

	return number, err
}
