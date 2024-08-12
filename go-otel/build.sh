#!/bin/sh
target=$1

usage() {
    echo "$0 client|server"
}

case $target in
    "server" )
     GOPROXY=https://goproxy.cn GOOS=linux GOARCH=amd64 go build  -o server server/server.go
     ;;
  "client" )
     GOPROXY=https://goproxy.cn GOOS=linux GOARCH=amd64 go build  -o client client/client.go
     ;;
 * )
     usage
     ;;
esac







