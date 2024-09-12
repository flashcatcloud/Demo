### 0x00 代码说明
完整部署该demo需要部署三个组件：
- skywalking后端
- nginx
- demo自身

1. demo程序里有一个`server`，一个`client`, `client`访问`server`经过`nginx`;

2. 服务器有个`/roll`接口，会去简单操作一下redis, redis默认db是`11`;

3. 客户端每隔30s会去访问服务端的`/roll`接口.

所以流程图如下所示:

`client -> nginx -> server -> redis` 

### 0x01 编译
编译包括代码二进制编译和镜像生成，过程都写在了`Dockerfile`中,简单执行`docker build`即可完成所有流程:

在 `build(172.26.88.122)`那台机器上, 将代码pull下来，cd到go-skywalking目录，执行`build --no-cache  -t flashcat.tencentcloudcr.com/flashcat/go-skywalking:$version .`

然后推送到仓库。

### 0x02 运行
按实际情况替换下面命令中的环境变量和镜像名.

#### 1. 运行skywalking(ui and webserver)

```shell
# 如果没有compose插件，请安装docker compose插件
cd ./skywalking

docker compose up -d

```

#### 2. 运行nginx(集成了skywalking lua 脚本的openrestry)

```shell
mkdir -p /datafc/skywalking-nginx/etc
cp nginx/nginx.conf /datafc/skywalking-nginx/etc


 docker run \
--name skywalking-nginx \
-v /datafc/skywalking-nginx/etc/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro \
-v /datafc/skywalking-nginx/logs:/data/nginx \
-p 9190:80 \
-d \
flashcat.tencentcloudcr.com/flashcat/nginx-skywalking:v0.0.1
```

> note: `flashcat.tencentcloudcr.com/flashcat/nginx-skywalking:$version` 基于`./nginx/Dockerfile`构建而来.

#### 3. 运行demo程序
```shell

docker run -d --name go-skywalking-demo --net=host \
-e GO_DEMO_SERVER_PORT=9191 \
-e DEMO_SERVER_ENDPOINT=http://localhost:9190/roll \
-e SW_AGENT_REPORTER_GRPC_BACKEND_SERVICE=localhost:11800 \
-e SW_AGENT_LOG_TRACING_KEY=SW_CTX \
-e SW_AGENT_LOG_TRACING_ENABLE=true \
-e SW_LOG_TYPE=auto \
-e REDIS_ADDR=10.201.0.210:6379 \
-e REDIS_PASSWORD=beaeb4c73 \
-v /datafc/go-skywalking-demo/logs:/app \
flashcat.tencentcloudcr.com/flashcat/go-skywalking:v0.0.1

```

### 0x03 日志采集
在flashcat `数据接入->数据采集`下，新建采集，`组件`留空，`插件类型`手动填写`logs-agent`,内容为`./log-scrape/logs.toml`

修改对应的`kafka`地址和`[logs.items]`下的`source`字段