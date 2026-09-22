FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/golang:1.23-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal

ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o categraf-operator ./cmd/operator

FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/alpine:3.20
RUN apk add --no-cache ca-certificates tzdata \
    && adduser -D -u 10001 -H appuser
COPY --from=builder /app/categraf-operator /usr/local/bin/categraf-operator
USER 10001:10001
ENTRYPOINT ["/usr/local/bin/categraf-operator"]
