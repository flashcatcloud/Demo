# 应用APM接入

通过 OpenTelemetry SDK 接入应用 Trace，主要有以下两种方式：

## 方式一：K8S Operator注入（推荐）

利用 OpenTelemetry Operator 的 Webhook 能力，在 Pod 创建时自动注入探针，无需修改应用代码。

### 通用前置步骤

#### 安装 cert\-manager

OpenTelemetry Operator 依赖 cert\-manager 管理 Webhook 证书。

```YAML
# 在线安装
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml

# 如无法访问 GitHub，可下载后本地执行
# kubectl apply -f ./cert-manager.yaml
```

验证 cert\-manager 正常运行：

```YAML
kubectl get deploy -n cert-manager
```

预期输出：

```YAML
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
cert-manager              1/1     1            1           5h47m
cert-manager-cainjector   1/1     1            1           5h47m
cert-manager-webhook      1/1     1            1           5h47m
```

#### 安装 OpenTelemetry Operator

```YAML
# 在线安装
kubectl apply -f     https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# 如无法访问 GitHub，可下载后本地执行
# kubectl apply -f ./opentelemetry-operator.yaml
```

> 💡 国内/离线环境
> 
> `ghcr.io` 镜像可能无法直接拉取，可改用华为云 SWR 国内镜像，例如 `0.153.0`：
> 
> `swr.cn-north-4.myhuaweicloud.com/ddn-k8s/ghcr.io/open-telemetry/opentelemetry-operator/opentelemetry-operator:0.153.0`
> 
> apply 完成后执行：
> 
> ```bash
> kubectl -n opentelemetry-operator-system set image deploy/opentelemetry-operator-controller-manager \
>   manager=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/ghcr.io/open-telemetry/opentelemetry-operator/opentelemetry-operator:0.153.0
> ```
> 

验证 Operator 正常运行：

```YAML
kubectl get deploy -n opentelemetry-operator-system
```

预期输出

```YAML
NAME                                        READY   UP-TO-DATE   AVAILABLE   AGE
opentelemetry-operator-controller-manager   1/1     1            1           5h37m
```

#### 创建 Instrumentation 资源

Instrumentation 是 Otel Operator 的 CRD，用于定义探针镜像和全局配置。

设计说明：本文采用集中管理模式，将 Instrumentation 统一放在 `opentelemetry-operator-system` 命名空间下，各业务命名空间的 Pod 通过跨空间引用即可接入，无需在每个业务命名空间重复创建。

> 💡 进阶技巧
> 
> 如果觉得每次写全路径太繁琐，可以在业务命名空间内部创建带 `app.kubernetes.io/default-instrumentation: "true"` 标签的 Instrumentation，之后该空间下的 Pod 注解只需写 `"true"` 即可。适用于各命名空间需要独立配置的场景。
> 
> 由于本文采用集中管理，已能满足大多数场景，无需在每个业务命名空间重复创建。
> 
> 



创建 `instrumentation.yaml`：

```YAML
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: instrumentation-sample
  namespace: opentelemetry-operator-system
  labels:
    # 该标签在同命名空间下才生效，对跨空间引用无影响，仅作示例
    app.kubernetes.io/default-instrumentation: "true"
spec:
  # 全局默认环境变量（适用于所有语言）
  env:
    # 【重要】请替换为实际 Collector 地址
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: http://10.99.1.6:4317
    - name: OTEL_EXPORTER_OTLP_PROTOCOL
      value: grpc
    - name: OTEL_LOGS_EXPORTER
      value: none
    - name: OTEL_METRICS_EXPORTER
      value: none
    # 建议显式设置服务名，否则 Operator 会从 Pod labels/name 推断
    # - name: OTEL_SERVICE_NAME
    #   value: unknown-service
    # 开启调试日志（排查问题时取消注释）
    # - name: OTEL_LOG_LEVEL
    #   value: debug

  # Java Agent 配置
  java:
    image: flashcat.tencentcloudcr.com/flashcat/autoinstrumentation-java:1.33.6

  # Python Agent 配置
  python:
    image: flashcat.tencentcloudcr.com/flashcat/autoinstrumentation-python:0.60b0
    # Python 特殊配置：该镜像缺少 gRPC 依赖，需覆盖为 HTTP 协议
    env:
      - name: OTEL_EXPORTER_OTLP_ENDPOINT
        value: http://10.99.1.6:4318   # HTTP 端口
      - name: OTEL_EXPORTER_OTLP_PROTOCOL
        value: http/protobuf
      - name: OTEL_LOGS_EXPORTER
        value: none
      - name: OTEL_METRICS_EXPORTER
        value: none
      # Python 调试日志（排查问题时取消注释）
      # - name: OTEL_PYTHON_LOG_LEVEL
      #   value: debug
```

核心配置字段说明：

> ⚠️ 重要说明：
> 
> - Java 应用使用全局配置（gRPC \+ 4317 端口）
> 
> - Python 应用使用语言级覆盖配置（HTTP/protobuf \+ 4318 端口），因为 `autoinstrumentation-python:0.60b0` 镜像未包含 gRPC 依赖库
> 
> - 请将 `OTEL_EXPORTER_OTLP_ENDPOINT` 的值替换为实际 Collector 地址
> 
> 

执行创建：

```YAML
kubectl apply -f ./instrumentation.yaml
```

### 应用接入

#### Java应用接入

##### 前置条件

- Java 版本：Java 8 及以上（推荐 Java 11\+）

- 应用类型：标准 Java 应用（Spring Boot、普通 Jar 包等）

##### 配置 Pod 注解

在需要接入的 Deployment 的 Pod template 中添加注解：

```YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-demo
  namespace: otel-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: java-demo
  template:
    metadata:
      labels:
        app: java-demo
      annotations:
        # 跨空间引用 Instrumentation：格式为 namespace/name
        instrumentation.opentelemetry.io/inject-java: "opentelemetry-operator-system/instrumentation-sample"
        # 如果本空间已有 Instrumentation，可简写为 "true"
    spec:
      containers:
      - name: java-demo
        image: flashcat.tencentcloudcr.com/flashcat/java-demo:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
```

##### 注入效果

Pod 创建后，Operator 会通过 Webhook 自动修改 Pod 配置：

1. **自动注入环境变量**

关键环境变量：

> 注意：如果用户已在 Pod 中定义了 `JAVA_TOOL_OPTIONS`，Operator 会追加 `-javaagent` 参数，不会覆盖已有值。
> 
> 

2. 自动注入 InitContainer

Operator 会注入一个 InitContainer，其作用是在 Pod 启动前，将 Java Agent Jar 包从 InitContainer 镜像复制到业务容器的共享卷中。

```YAML
InitContainer: opentelemetry-auto-instrumentation
  → 复制 /otel/opentelemetry-javaagent.jar 到 emptyDir 共享卷
  → 业务容器通过 -javaagent:/otel/... 挂载使用
```

##### 验证接入

```YAML
# 查看 Pod 是否成功注入 InitContainer
kubectl describe pod <pod-name> -n otel-demo

# 查看 Pod 环境变量
kubectl exec <pod-name> -n otel-demo -- env | grep OTEL

# 查看 Java Agent 是否生效
kubectl logs <pod-name> -n otel-demo | grep -i opentelemetry
```



#### Python 应用接入

##### 前置条件

- Python 版本：Python 3\.8 及以上（`opentelemetry-instrument` 0\.60b0 已停止支持 Python 3\.7）

- 应用类型：标准 Python 应用（Flask、Django、FastAPI 等）

##### 配置 Pod 注解

与 Java 类似，但注解键名不同：

```YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-demo
  namespace: otel-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: python-demo
  template:
    metadata:
      labels:
        app: python-demo
      annotations:
        # Python 使用 inject-python
        instrumentation.opentelemetry.io/inject-python: "opentelemetry-operator-system/instrumentation-sample"
    spec:
      imagePullSecrets:
        - name: tcr-flashcat
      containers:
      - name: python-demo
        image: flashcat.tencentcloudcr.com/flashcat/python-demo:0.0.6
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
```

##### 注入效果

1. 自动注入环境变量

关键环境变量：

2. 自动注入 InitContainer

与 Java 类似，InitContainer 将 Python 自动插桩包复制到业务容器：

```YAML
InitContainer: opentelemetry-auto-instrumentation
  → 复制 Python 插桩包到共享卷
  → 业务容器通过环境变量 OTEL_PYTHON_... 启用插桩
```

##### 验证接入

```YAML
# 查看 Pod 注入状态
kubectl describe pod <pod-name> -n otel-demo

# 查看 Python 插桩日志
kubectl logs <pod-name> -n otel-demo | grep -i opentelemetry
```



#### 附录 1：Webhook 失败策略说明

Operator 的 Webhook 配置中，作用于 Pod 的 `mpod.kb.io` 的 `failurePolicy` 为 `Ignore`：

结论：即使注入失败，也不会阻塞 Pod 的正常启动流程，保证了业务可用性。



## 方式二：镜像内置 Agent（适用于有 CI/CD 流程）

在构建镜像时将 OpenTelemetry Agent 打包进去，部署时仅需配置环境变量，不依赖 Kubernetes Webhook 注入，也无需修改应用代码。

以 Java 为例。

#### 准备 Agent

建议固定 Agent 版本，避免使用 `latest` 导致构建结果不可控；Agent 版本建议与 Instrumentation 使用的 `1.33.6` 保持一致。

在线构建时可从 GitHub 固定版本下载：

```Dockerfile
FROM eclipse-temurin:21-jre AS builder
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v1.33.6/opentelemetry-javaagent.jar /otel/opentelemetry-javaagent.jar
```

国内或离线环境建议提前把 jar 下载到构建机，再通过 `COPY` 放入镜像，避免构建时访问 GitHub：

```Dockerfile
FROM eclipse-temurin:21-jre AS builder
COPY opentelemetry-javaagent.jar /otel/opentelemetry-javaagent.jar
```

#### 构建应用镜像

```Dockerfile
FROM eclipse-temurin:21-jre
COPY --from=builder /otel/opentelemetry-javaagent.jar /otel/opentelemetry-javaagent.jar
COPY my-app.jar /app/my-app.jar
WORKDIR /app

ENTRYPOINT ["java", "-jar", "my-app.jar"]
```

#### 部署配置

通过 `JAVA_TOOL_OPTIONS` 在启动时挂载 Agent，并显式声明 OTLP 上报协议：

```YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        env:
        - name: JAVA_TOOL_OPTIONS
          value: >-
            -javaagent:/otel/opentelemetry-javaagent.jar
            -Dotel.service.name=my-service
            -Dotel.traces.exporter=otlp
            -Dotel.exporter.otlp.protocol=http/protobuf
            -Dotel.exporter.otlp.endpoint=http://otel-collector:4318
```

> 如果 Collector 只提供 gRPC 端口，将 `-Dotel.exporter.otlp.protocol` 改为 `grpc`，endpoint 改为 `http://otel-collector:4317`。

> `JAVA_TOOL_OPTIONS` 会作用于容器内所有 JVM 进程；如果镜像中包含多个 Java 入口，需要注意影响范围。

#### 验证接入

```YAML
# 查看 Agent 是否启动
kubectl logs <pod-name> -n <namespace> | grep -i opentelemetry

# 查看上报配置
kubectl exec <pod-name> -n <namespace> -- env | grep JAVA_TOOL_OPTIONS
```

启动日志中出现 `opentelemetry-javaagent - version` 即表示 Agent 加载成功。

优点：

- 镜像即交付，不依赖 Kubernetes 特定能力

- 环境变量统一管理，部署配置清晰

- 适用于有 CI/CD 流程、能控制镜像构建的团队

## 其他语言参考文档

|语言 / 框架|文档|
|---|---|
|Go|[Flashcat APM Go 接入](http://10.99.1.11/docs/content/flashcat/trace/integration/flashcat_apm_golang/)|
|Nginx|[Nginx SkyWalking 接入](http://10.99.1.11/docs/content/flashcat/trace/integration/nginx_skywalking/)|
|Spring Cloud Gateway|[OpenTelemetry](http://10.99.1.11/docs/content/flashcat/trace/integration/spring-cloud-gateway-opentelementry/) · [SkyWalking](http://10.99.1.11/docs/content/flashcat/trace/integration/spring-cloud-gateway-skywalking/)|
|Spring Boot 日志 TraceId|[Logback 接入](http://10.99.1.11/docs/content/flashcat/trace/integration/springboot-logback-print-trace/)|

## 通用故障排查指南

检查 Operator 状态

```YAML
kubectl get pods -n opentelemetry-operator-system
kubectl logs -n opentelemetry-operator-system <operator-pod>
```

检查 Pod 是否被正确注入

```YAML
# 查看 Pod 的 InitContainers 是否增加
kubectl describe pod <pod-name> -n <namespace>

# 查看环境变量
kubectl exec <pod-name> -n <namespace> -- env | grep -E "OTEL|JAVA_TOOL_OPTIONS"
```

检查数据上报

```YAML
# 查看应用日志中是否有 OTLP 导出错误
kubectl logs <pod-name> -n <namespace> | grep -i "otlp\|export\|error"
```

开启调试日志

```YAML
# Java 调试日志
- name: OTEL_LOG_LEVEL
  value: debug

# Python 调试日志  
- name: OTEL_PYTHON_LOG_LEVEL
  value: debug
```

常见问题

