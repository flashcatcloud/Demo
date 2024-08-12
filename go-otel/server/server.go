package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"

	"github.com/flashcatcloud/Demo/go-otel/pkg/trace"
)

var (
	// 初始化
	opsProcessed = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "myapp_processed_ops_total",
		Help: "The total number of processed events",
	})
	tracer = otel.Tracer("roll")

	rdb *redis.Client
)

func init() {
	rdb = redis.NewClient(&redis.Options{
		Addr: os.Getenv("REDIS_ADDR"),
	})
}

func recordMetrics() {
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

func main() {
	// 平滑处理 SIGINT (CTRL+C) .
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	recordMetrics()

	// 设置 OpenTelemetry.
	otelShutdown, err := trace.SetupOTelSDK(ctx)
	if err != nil {
		return
	}
	// 妥善处理停机，确保无泄漏
	defer func() {
		err = errors.Join(err, otelShutdown(ctx))
	}()

	// 启用 tracing
	if err := redisotel.InstrumentTracing(rdb); err != nil {
		panic(err)
	}

	r := gin.Default()
	r.Use(otelgin.Middleware(os.Getenv("OTEL_SERVICE_NAME")))

	r.GET("/", func(c *gin.Context) {
		c.String(200, "Hello, World!")
	})

	// 添加metrics接口
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))
	r.GET("/roll", roll)

	r.Run(":8080")
}

func roll(c *gin.Context) {
	ctx, span := tracer.Start(c.Request.Context(), "roll") // 开始 span
	defer span.End()                                       // 结束 span

	number := rollOnce(ctx)

	rollValueAttr := attribute.Int("roll.value", number)
	span.SetAttributes(rollValueAttr, attribute.String("company", "flashcat")) // span 添加属性

	opsProcessed.Inc()
	// 摇骰子次数的指标 +1
	// rollCnt.Add(ctx, 1, metric.WithAttributes(rollValueAttr))

	c.JSON(http.StatusOK, gin.H{"msg": number})
}

func rollOnce(ctx context.Context) int {
	ctx, span := otel.Tracer("child").Start(ctx, "rollOnce") // 开始 span
	defer span.End()
	span.SetAttributes(attribute.String("function", "rollOnce"))

	number := 1 + rand.Intn(6)
	if err := doSomething(ctx, rdb); err != nil {
		log.Printf("doSomething failed:%v\n!", err)
	}

	return number
}

func doSomething(ctx context.Context, rdb *redis.Client) error {
	if err := rdb.Set(ctx, "hello", "world", time.Minute).Err(); err != nil {
		return err
	}
	if err := rdb.Set(ctx, "tag", "OTel", time.Minute).Err(); err != nil {
		return err
	}

	val := rdb.Get(ctx, "tag").Val()
	if val != "OTel" {
		return errors.New("tag not found")
	}

	if err := rdb.Del(ctx, "name").Err(); err != nil {
		return err
	}
	if err := rdb.Del(ctx, "tag").Err(); err != nil {
		return err
	}
	log.Println("access redis done!")
	return nil
}
