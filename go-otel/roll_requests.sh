#!/bin/bash

# 定义服务器URL
SERVER_URL="http://localhost:${GO_DEMO_SERVER_PORT:-8080}"

echo "Starting to request /roll endpoint every 60 seconds..."
echo "Press Ctrl+C to stop"

while true; do
  echo "$(date) - Requesting /roll endpoint"
  curl -s "${SERVER_URL}/roll"
  echo -e "\n"
  sleep 60
done 