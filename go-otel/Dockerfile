FROM golang:1.22.6 as build
WORKDIR /app/
COPY . /app
RUN go env -w  GOPROXY=https://goproxy.cn,direct && \
    go build -o server server/server.go && \
    go build -o client client/client.go

FROM flashcat.tencentcloudcr.com/flashcat/centos:7.9.7
COPY --from=build /app/server  /home/flashcat/server/server
COPY ./server/start.sh  /home/flashcat/server/start.sh
COPY --from=build /app/client  /home/flashcat/client/client
COPY ./client/start.sh  /home/flashcat/client/start.sh
COPY start.sh /home/flashcat/start.sh

CMD ["/home/flashcat/start.sh"]
