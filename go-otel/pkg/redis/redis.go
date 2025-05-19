package redis

import (
	"os"
	"strconv"
	"log"
	"time"
	"context"
	"math/rand"
	"errors"

	"github.com/redis/go-redis/v9"
	"github.com/redis/go-redis/extra/redisotel/v9"
	logx "github.com/flashcatcloud/Demo/go-otel/pkg/log"
)

var Rdb *redis.Client

func Init() {
	initRedis()
	// 启用 tracing
	if err := redisotel.InstrumentTracing(Rdb); err != nil {
		panic(err)
	}
}

func initRedis() {
	var db int
	dbStr := os.Getenv("REDIS_DB")
	if dbStr == "" {
		db = 11
	} else {
		db, _ = strconv.Atoi(dbStr)
	}

	log.Printf("db:%v,addr:%v, passwd:%v\n", db, os.Getenv("REDIS_ADDR"), os.Getenv("REDIS_PASSWORD"))
	Rdb = redis.NewClient(&redis.Options{
		Addr:     os.Getenv("REDIS_ADDR"),
		Password: os.Getenv("REDIS_PASSWORD"),
		DB:       db,
	})
}

func DoSomething(ctx context.Context, rdb *redis.Client) error {
	// 6% 概率返回错误
	if rand.Float64() < 0.2 {
		return errors.New("random error for testing")
	}

	if err := rdb.Set(ctx, "go-demo:hello", "world", time.Minute).Err(); err != nil {
		return err
	}
	logx.Logger.InfoContext(ctx, "go-demo:hello set")
	if err := rdb.Set(ctx, "go-demo:tag", "OTel", time.Minute).Err(); err != nil {
		return err
	}
	logx.Logger.InfoContext(ctx, "go-demo:tag set")

	val := rdb.Get(ctx, "go-demo:tag").Val()
	if val != "OTel" {
		return errors.New("tag not found")
	}

	if err := rdb.Del(ctx, "go-demo:name").Err(); err != nil {
		return err
	}
	logx.Logger.With("hello", "flashcat").InfoContext(ctx, "go-demo:name deleted")
	if err := rdb.Del(ctx, "go-demo:tag").Err(); err != nil {
		return err
	}
	logx.Logger.InfoContext(ctx, "tag deleted")
	return nil
}
