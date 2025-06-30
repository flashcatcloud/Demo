#!/bin/bash

sh /home/flashcat/server/start.sh
# 等待server监听端口
#!/bin/bash

# 要检查的端口号
PORT=$GO_DEMO_SERVER_PORT

# 无限循环，直到端口开始监听
while true; do
    if curl localhost:$PORT; then
        echo "Port $PORT is now listening."
        break
    else
        echo "Port $PORT is not listening yet. Checking again in 5 seconds..."
        sleep 5
    fi
done

# 脚本结束

# mcp-server
sh /home/flashcat/mcp-server/start.sh

# client
sh /home/flashcat/client/start.sh


while true; do
    sleep 1
done