### 代码说明
这个项目中有一个服务器，一个客户端。
服务器有个`/roll`接口，会去简单操作一下redis, redis默认db是`11`.

客户端每隔30s会去访问服务端的`/roll`接口.

### 编译
编译包括代码二进制编译和镜像生成，过程都写在了`Dockerfile`中,简单执行`docker build`即可完成所有流程:

在 `build(172.26.88.122)`那台机器上, 将代码pull下来，cd到go-skywalking目录，执行`build --no-cache  -t flashcat.tencentcloudcr.com/flashcat/go-skywalking:$version .`

然后推送到仓库。

### 运行
按实际情况替换下面命令中的环境变量和镜像名.

#### 1. 运行skywalking(ui and webserver)

```shell
# 如果没有compose插件，请安装docker compose插件
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

### 日志采集
在flashcat `数据接入->数据采集`下，新建采集，`组件`留空，`插件类型`手动填写`logs-agent`,内容如下, 修改对应的`kafka`地址和`[logs.items]`下的`source`字段
```toml
[logs]
## just a placholder
api_key = "ef4ahfbwzwwtlwfpbertgq1i6mq0ab1q"
## enable log collect or not
enable = true
## the server receive logs, http/tcp/kafka, only kafka brokers can be multiple ip:ports with concatenation character ","
send_to = "10.201.0.210:9092"
## send logs with protocol: http/tcp/kafka
send_type = "kafka"

## send logs with compression or not 
use_compression = false
# gzip压缩级别,0 表示不压缩， 1-9 表示压缩级别
compression_level=0

#kafka支持的压缩 none gzip snappy lz4 zstd
compression_codec="none"

## use ssl or not
send_with_tls = false
## send logs in batchs
batch_wait = 5
## save offset in this path 
run_path = "/opt/categraf/run"
## max files can be open 
open_files_limit = 2000
## scan config file in 10 seconds
scan_period = 10
## read buffer of udp 
frame_size = 9000
## channal size, default 100 

## 读取日志缓冲区，行数
chan_size = 10
## 有多少线程处理日志
pipeline=10
## configuration for kafka
## 指定kafka版本
kafka_version="3.3.2"
# 默认0 表示按照读取顺序串行写入kafka,如果对日志顺序有要求,保持默认配置
batch_max_concurrence = 100
# 发送缓冲区的大小(行数)，如果设置比chan_size小，会自动设置为跟chan_size相同
batch_max_size=1
# 每次最大发送的内容上限 默认1000000 Byte (与batch_max_size先到者触发发送)
batch_max_content_size=900000 
# client timeout in seconds
producer_timeout= 10

# 是否开启sasl模式
sasl_enable = false
sasl_user = "admin"
sasl_password = "admin"
# PLAIN 
sasl_mechanism= "PLAIN"
# v1
sasl_version=1
# set true
sasl_handshake = true
# optional
# sasl_auth_identity=""

##
#ent-v0.3.50以上版本新增,是否开启pod日志采集
enable_collect_container=false

#是否采集所有pod的stdout stderr
collect_container_all = false
  ## glog processing rules
  # [[logs.processing_rules]]
  ## single log configure
  [[logs.items]]
  ## file/journald/tcp/udp
  type = "file"
  ## type=file, path is required; type=journald/tcp/udp, port is required
  path = "/datafc/skywalking-nginx/logs/access.log"
  topic = "go-skywalking-demo-nginx"
  source = "demo03"
  service = "skywalking-nginx"

  [[logs.items]]
  ## file/journald/tcp/udp
  type = "file"
  ## type=file, path is required; type=journald/tcp/udp, port is required
  path = "/datafc/go-skywalking-demo/logs/demo.log"
  topic = "go-skywalking-demo"
  source = "demo03"
  service = "go-skywalking-demo"

```