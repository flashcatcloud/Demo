FROM flashcat.tencentcloudcr.com/flashcat/golang:1.22.6
WORKDIR /app/
COPY . /app
RUN go env -w  GOPROXY=https://goproxy.cn,direct && \
    go build -o /app/bin/server server/server.go && \
    go build -o /app/bin/client client/client.go && \
    mkdir /home/flashcat/server && \
    mkdir /home/flashcat/client && \
    cp /app/bin/server  /home/flashcat/server && \
    cp /app/bin/client  /home/flashcat/client && \
    cp ./server/start.sh  /home/flashcat/server/start.sh && \
    cp ./client/start.sh  /home/flashcat/client/start.sh && \
    cp start.sh /home/flashcat/start.sh &&  \
    chmod +x /home/flashcat/start.sh /home/flashcat/server/start.sh /home/flashcat/client/start.sh && \
    rm -rf /app

CMD ["/home/flashcat/start.sh"]