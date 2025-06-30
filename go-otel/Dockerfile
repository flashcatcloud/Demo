# 第一阶段：构建二进制
FROM flashcat.tencentcloudcr.com/flashcat/golang:1.22.6 AS builder
WORKDIR /app
COPY . /app
RUN go mod tidy && \
    go env -w  GOPROXY=https://goproxy.cn,direct && \
    go build -o /app/bin/server ./server && \
    go build -o /app/bin/client ./client && \
    go build -o /app/bin/mcp-server ./mcp-server/

# 第二阶段：准备运行环境
FROM flashcat.tencentcloudcr.com/flashcat/centos:7.9.6
WORKDIR /home/flashcat

# 拷贝二进制文件
COPY --from=builder /app/bin/server /home/flashcat/server/server
COPY --from=builder /app/bin/client /home/flashcat/client/client
COPY --from=builder /app/bin/mcp-server /home/flashcat/mcp-server/server

# 拷贝启动脚本
COPY server/start.sh /home/flashcat/server/start.sh
COPY client/start.sh /home/flashcat/client/start.sh
COPY mcp-server/start.sh /home/flashcat/mcp-server/start.sh
COPY start.sh /home/flashcat/start.sh

RUN chmod +x /home/flashcat/start.sh /home/flashcat/server/start.sh /home/flashcat/client/start.sh /home/flashcat/mcp-server/start.sh

CMD ["/home/flashcat/start.sh"]