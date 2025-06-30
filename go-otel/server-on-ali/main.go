package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/gin-contrib/pprof"
	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"

	"github.com/flashcatcloud/Demo/go-otel/pkg/model"
	"github.com/flashcatcloud/Demo/go-otel/pkg/redis"
	pkgotel "github.com/flashcatcloud/Demo/go-otel/pkg/otel"
)

func init() {
	redis.Init()
	model.Init()
}

func main() {
	// 平滑处理 SIGINT (CTRL+C) .
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdown := pkgotel.InitOpenTelemetry()
	defer shutdown()

	model.RecordMetrics()

	r := gin.Default()
	r.Use(otelgin.Middleware(os.Getenv("OTEL_SERVICE_NAME")))
	pprof.Register(r)

	r.GET("/", func(c *gin.Context) {
		c.String(200, "Hello, World!")
	})

	// 添加metrics接口
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))
	r.GET("/roll", model.Roll)
	r.POST("/roll2", model.Roll)

	r.POST("/user", model.CreateUser)
	r.GET("/user", model.GetUser)
	r.GET("/users", model.ListUsers)

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

func parentMethod(ctx context.Context) {
	tracer := otel.Tracer("otel-go-tracer")
	ctx, span := tracer.Start(ctx, "parent span")
	fmt.Println(span.SpanContext().TraceID()) // 打印 TraceId
	span.SetAttributes(attribute.String("key", "value"))
	span.SetStatus(codes.Ok, "Success")
	childMethod(ctx)
	span.End()
}

func childMethod(ctx context.Context) {
	tracer := otel.Tracer("otel-go-tracer")
	ctx, span := tracer.Start(ctx, "child span")
	span.SetStatus(codes.Ok, "Success")
	grandChildMethod(ctx)
	span.End()
}

func grandChildMethod(ctx context.Context) {
	tracer := otel.Tracer("otel-go-tracer")
	ctx, span := tracer.Start(ctx, "grandchild span")
	span.SetStatus(codes.Error, "error")

	// 业务代码...

	span.End()
}
