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
	"strconv"
	"syscall"
	"time"

	"github.com/gin-contrib/pprof"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/bridges/otelslog"
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
	logger = otelslog.NewLogger("go-demo-server")
	rdb    *redis.Client
)

func init() {
	var db int
	dbStr := os.Getenv("REDIS_DB")
	if dbStr == "" {
		db = 11
	} else {
		db, _ = strconv.Atoi(dbStr)
	}

	rdb = redis.NewClient(&redis.Options{
		Addr:     os.Getenv("REDIS_ADDR"),
		Password: os.Getenv("REDIS_PASSWORD"),
		DB:       db,
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
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
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
	pprof.Register(r)

	r.GET("/", func(c *gin.Context) {
		c.String(200, "Hello, World!")
	})

	// 添加metrics接口
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))
	r.GET("/roll", roll)

	srv := http.Server{
		Addr:    fmt.Sprintf(":%s", os.Getenv("GO_DEMO_SERVER_PORT")),
		Handler: r,
	}

	//启动HTTP服务器
	srvErr := make(chan error, 1)
	go func() {
		srvErr <- srv.ListenAndServe()
	}()

	// Wait for interruption.
	select {
	case err = <-srvErr:
		// Error when starting HTTP server.
		return
	case <-ctx.Done():
		// Wait for first CTRL+C.
		// Stop receiving signal notifications as soon as possible.
		stop()
	}

	// When Shutdown is called, ListenAndServe immediately returns ErrServerClosed.
	if err = srv.Shutdown(context.Background()); err != nil {
		log.Fatal("Server Shutdown:", err)
	}
	log.Println("Server exiting")
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
	logger.InfoContext(ctx, fmt.Sprintf("roll number:%d", number))

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

	logger.InfoContext(ctx, fmt.Sprintf("rollOnce number:%d", number))

	return number
}

func doSomething(ctx context.Context, rdb *redis.Client) error {
	if err := rdb.Set(ctx, "go-demo:hello", "world", time.Minute).Err(); err != nil {
		return err
	}
	logger.InfoContext(ctx, "go-demo:hello set")
	if err := rdb.Set(ctx, "go-demo:tag", "OTel", time.Minute).Err(); err != nil {
		return err
	}
	logger.InfoContext(ctx, "go-demo:tag set")

	val := rdb.Get(ctx, "go-demo:tag").Val()
	if val != "OTel" {
		return errors.New("tag not found")
	}

	if err := rdb.Del(ctx, "go-demo:name").Err(); err != nil {
		return err
	}
	logger.With("hello", "flashcat").InfoContext(ctx, "go-demo:name deleted")
	if err := rdb.Del(ctx, "go-demo:tag").Err(); err != nil {
		return err
	}
	logger.InfoContext(ctx, "tag deleted")
	return nil
}
