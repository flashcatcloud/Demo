package logx

import "go.opentelemetry.io/contrib/bridges/otelslog"

var Logger = otelslog.NewLogger("go-demo-server")
