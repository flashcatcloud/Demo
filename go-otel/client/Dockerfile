# 使用官方Go运行时作为父镜像
FROM golang:1.23-alpine AS builder

# 设置工作目录
WORKDIR /app

# 复制go mod和sum文件
COPY go.mod go.sum ./

# 下载依赖项
RUN go mod download

# 复制源代码
COPY . .

# 构建应用程序
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o client ./client

# 使用alpine作为最终镜像
FROM alpine:latest

# 安装ca-certificates和tzdata
RUN apk --no-cache add ca-certificates tzdata

WORKDIR /root/

# 从builder阶段复制构建的应用程序
COPY --from=builder /app/client .

# 运行应用程序
CMD ["./client"] 