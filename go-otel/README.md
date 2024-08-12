### 代码说明
这个项目中有一个服务器，一个客户端。
服务器有个`/roll`接口，会去简单操作一下redis, redis默认db是`11`.

客户端每隔30s会去访问服务端的`/roll`接口.

### 编译
编译包括代码二进制编译和镜像生成，过程都写在了`Dockerfile`中,简单执行`docker build`即可完成所有流程:

在 `build(172.26.88.122)`那台机器上, 将代码pull下来，cd到go-otel目录，执行`build --no-cache  -t flashcat.tencentcloudcr.com/flashcat/go-otel:$version .`

然后推送到仓库。

### 运行
按实际情况替换下面命令中的环境变量和镜像名.
```shell

docker run -d --name go-otel-demo --net=host \ 
-e GO_DEMO_SERVER_PORT=9191 \
-e OTEL_EXPORTER_OTLP_ENDPOINT=localhost:4318 \ 
-e REDIS_ADDR=10.201.0.210:6379 \
-e REDIS_PASSWORD=beaeb4c73 \ 
flashcat.tencentcloudcr.com/flashcat/go-otel:v0.0.3

```
