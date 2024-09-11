package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"log/slog"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	_ "github.com/apache/skywalking-go"
	"github.com/apache/skywalking-go/toolkit/trace"
	"github.com/gin-contrib/pprof"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
	sloglogrus "github.com/samber/slog-logrus/v2"
	"github.com/sirupsen/logrus"
	"gopkg.in/natefinch/lumberjack.v2"
)

var (
	// 初始化
	opsProcessed = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "myapp_processed_ops_total",
		Help: "The total number of processed events",
	})
	rdb    *redis.Client
	rng    *rand.Rand
	logger *slog.Logger
)

func initLog() {
	logrusLogger := logrus.New()
	// 格式使用json
	logrusLogger.SetFormatter(&logrus.JSONFormatter{})
	// 使用lumberjack帮忙rotate
	lumberjackLogger := &lumberjack.Logger{
		Filename:   filepath.ToSlash("./demo.log"),
		MaxSize:    100, // MB
		MaxBackups: 10,
		MaxAge:     30,   // days
		Compress:   true, // disabled by default
	}

	// 如果不想在应用内rotate, 可以直接打开一个文件，将文件描述符传递给logrusLogger
	// 然后使用系统上的rotate工具
	// 如果不想写文件，可以直接传入os.Stdout
	logrusLogger.SetOutput(lumberjackLogger)

	logger = slog.New(sloglogrus.Option{Level: slog.LevelDebug, Logger: logrusLogger}.NewLogrusHandler())
	logger = logger.
		With("environment", "dev").
		With("release", "v0.0.1")
}

func init() {
	initLog()
	initRedis()
}

func initRedis() {
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
	rng = rand.New(rand.NewSource(time.Now().UnixNano()))

	// 平滑处理 SIGINT (CTRL+C) .
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	recordMetrics()

	r := gin.Default()
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

	var err error
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
	ctx := c.Request.Context()
	number := rollOnce(ctx)

	opsProcessed.Inc()
	// 摇骰子次数的指标 +1
	// rollCnt.Add(ctx, 1, metric.WithAttributes(rollValueAttr))
	logger.InfoContext(ctx, fmt.Sprintf("roll number:%d", number))

	c.JSON(http.StatusOK, gin.H{"msg": number})
}

func rollOnce(ctx context.Context) int {
	span, _ := trace.CreateLocalSpan("rollOnce")
	span.SetTag("a", "b")
	defer trace.StopSpan()

	slackOff()

	number := 1 + rng.Intn(6)
	if err := doSomething(ctx, rdb); err != nil {
		log.Printf("doSomething failed:%v\n!", err)
	}

	logger.InfoContext(ctx, fmt.Sprintf("rollOnce number:%d", number))

	return number
}

func slackOff() {
	span, _ := trace.CreateLocalSpan("sleeping")
	span.SetTag("hello", "world")
	defer trace.StopSpan()

	time.Sleep(time.Duration(rng.Intn(2000)) * time.Microsecond)
}

func doSomething(ctx context.Context, rdb *redis.Client) error {
	span, _ := trace.CreateLocalSpan("doSomething")
	span.SetTag("c", "d")
	defer trace.StopSpan()

	if err := rdb.Set(ctx, "go-demo:hello", "world", time.Minute).Err(); err != nil {
		return err
	}
	logger.InfoContext(ctx, "go-demo:hello set")
	if err := rdb.Set(ctx, "go-demo:tag", "skywalking", time.Minute).Err(); err != nil {
		return err
	}
	logger.InfoContext(ctx, "go-demo:tag set")

	val := rdb.Get(ctx, "go-demo:tag").Val()
	if val != "skywalking" {
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
