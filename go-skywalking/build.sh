#!/bin/sh

target=$1
SW_GO_AGENT_PATH=$2

usage() {
    echo "Usage: $0 {client|server} [SW_GO_AGENT_PATH]"
    echo "  client|server: Target to build."
    echo "  SW_GO_AGENT_PATH: Path to the SkyWalking Go agent."
}

case $target in
    "server" )
     GOPROXY=https://goproxy.cn GOOS=linux GOARCH=amd64 go build -toolexec="${SW_GO_AGENT_PATH}"  -o server server/server.go
     ;;
  "client" )
     GOPROXY=https://goproxy.cn GOOS=linux GOARCH=amd64 go build -toolexec="${SW_GO_AGENT_PATH}" -o client client/client.go
     ;;
 * )
     usage
     ;;
esac







