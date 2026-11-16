{{- define "categraf.nodeHostnameExpr" -}}
{{- $hname := default "nodeName" .Values.nodeCategraf.hostname }}
{{- $hostnameExpr := $hname }}
{{- if eq $hname "nodeName" }}
{{- $hostnameExpr = "${HOSTNAME}" }}
{{- else if eq $hname "hostname" }}
{{- $hostnameExpr = "$hostname" }}
{{- else }}
{{- $hostnameExpr = replace "${hostname}" "$hostname" $hostnameExpr }}
{{- $hostnameExpr = replace "${ip}" "$ip" $hostnameExpr }}
{{- $hostnameExpr = replace "${cluster}" "${CLUSTER_NAME}" $hostnameExpr }}
{{- $hostnameExpr = replace "${nodeName}" "${HOSTNAME}" $hostnameExpr }}
{{- end }}
{{- $hostnameExpr }}
{{- end }}

{{- define "categraf.nodeConfigToml" -}}
[global]
print_configs = false
hostname = "{{ include "categraf.nodeHostnameExpr" . }}"
omit_hostname = false
precision = "ms"
interval = {{ int (dig "config" "interval" 15 .Values.categraf) }}
providers = ["local", "http", "rmq"]
[global.labels]
env = "{{ .Values.categraf.env }}"
cluster = "{{ .Values.categraf.clusterName }}"
categraf = "nodeAgent"
{{- with .Values.categraf.customLabels }}
{{- include "categraf.validateCustomLabels" . }}
{{- range $key, $value := . }}
{{ $key | toString }} = {{ $value | toString | quote }}
{{- end }}
{{- end }}

[global.n9e_server]
address="{{ include "categraf.serverAddr" . }}"
[writer_opt]
batch = {{ int (default 2000 (dig "writer" "batch" 0 .Values.categraf)) }}
chan_size = {{ int (dig "writer" "chanSize" 1000000 .Values.categraf) }}
[heartbeat]
enable = true
url = "{{ include "categraf.heartbeatURL" . }}"
interval = {{ int (dig "heartbeat" "interval" 10 .Values.categraf) }}
timeout = {{ int (dig "heartbeat" "timeout" 5000 .Values.categraf) }}
dial_timeout = {{ int (dig "heartbeat" "dialTimeout" 2500 .Values.categraf) }}
{{- end }}

{{- define "categraf.ksmConfigToml" -}}
[global]
interval = {{ int (dig "config" "interval" 15 .Values.categraf) }}
providers = ["local"]
hostname = "${CLUSTER_NAME}-${HOSTNAME}"
[global.labels]
env = "{{ .Values.categraf.env }}"
cluster = "{{ .Values.categraf.clusterName }}"
categraf = "ksmAgent"
{{- with .Values.categraf.customLabels }}
{{- include "categraf.validateCustomLabels" . }}
{{- range $key, $value := . }}
{{ $key | toString }} = {{ $value | toString | quote }}
{{- end }}
{{- end }}

[global.n9e_server]
address="{{ include "categraf.serverAddr" . }}"
[writer_opt]
batch = {{ int (default 1000 (dig "writer" "batch" 0 .Values.categraf)) }}
chan_size = {{ int (dig "writer" "chanSize" 1000000 .Values.categraf) }}
[heartbeat]
enable = true
url = "{{ include "categraf.heartbeatURL" . }}"
interval = {{ int (dig "heartbeat" "interval" 10 .Values.categraf) }}
timeout = {{ int (dig "heartbeat" "timeout" 5000 .Values.categraf) }}
dial_timeout = {{ int (dig "heartbeat" "dialTimeout" 2500 .Values.categraf) }}
[prometheus]
enable = true
scrape_config_file = "/etc/categraf/cluster-scrape.yaml"
log_level = "info"
{{- end }}

{{- define "categraf.ksmScrapeYaml" -}}
global:
  scrape_interval: {{ int (default 15 (dig "prometheus" "scrapeInterval" 0 .Values.categraf)) }}s
  external_labels:
    cluster: "{{ .Values.categraf.clusterName }}"
    {{- with .Values.categraf.customLabels }}
    {{- include "categraf.validateCustomLabels" . }}
    {{- range $key, $value := . }}
    {{ $key }}: {{ $value | toString | quote }}
    {{- end }}
    {{- end }}
    
scrape_configs:
  {{- if .Values.ksmCategraf.jobs.kubeStateMetrics }}
  - job_name: 'kube-state-metrics'
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: {{ include "categraf.namespace" . }};{{ include "categraf.resourceName" (dict "root" . "suffix" "kube-state-metrics") }};http-metrics
  {{- end }}
  {{- if .Values.appMetrics.enabled }}
  {{- if not (kindIs "slice" .Values.appMetrics.extraScrapeConfigs) }}
  {{- fail "appMetrics.extraScrapeConfigs must be a list" }}
  {{- end }}
  {{- if .Values.appMetrics.defaultJob.enabled }}
  - job_name: 'app-metrics'
    metrics_path: /metrics
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: service
        regex: ^(.+)$
        replacement: $1
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        target_label: service
        regex: ^(.+)$
        replacement: $1
      - source_labels: [__meta_kubernetes_pod_label_team]
        target_label: team
        regex: ^(.+)$
        replacement: $1
      - source_labels: [__meta_kubernetes_pod_ip, __meta_kubernetes_pod_annotation_prometheus_io_port]
        target_label: __address__
        regex: (.+);(\d+)
        replacement: "${1}:${2}"
      - target_label: __metrics_path__
        replacement: "/metrics"
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        target_label: __metrics_path__
        regex: ^(.+)$
        replacement: $1
      - target_label: __scheme__
        replacement: http
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
        target_label: __scheme__
        regex: ^(https?)$
        replacement: $1
  {{- end }}
  {{- range .Values.appMetrics.extraScrapeConfigs }}
  {{- toYaml (list .) | nindent 2 }}
  {{- end }}
  {{- end }}
  {{- if .Values.controlPlane.enabled }}
  - job_name: 'apiserver'
    kubernetes_sd_configs:
      - role: endpoints
    scheme: https
    tls_config:
      insecure_skip_verify: true
    authorization:
      type: Bearer
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: default;kubernetes;https

  - job_name: 'kube-controller-manager'
    kubernetes_sd_configs:
      - role: pod
    scheme: https
    tls_config:
      insecure_skip_verify: true
    authorization:
      type: Bearer
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_component]
        action: keep
        regex: kube-system;kube-controller-manager
      - source_labels: [__meta_kubernetes_pod_ip]
        action: replace
        target_label: __address__
        replacement: ${1}:10257

  - job_name: 'kube-scheduler'
    kubernetes_sd_configs:
      - role: pod
    scheme: https
    tls_config:
      insecure_skip_verify: true
    authorization:
      type: Bearer
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_component]
        action: keep
        regex: kube-system;kube-scheduler
      - source_labels: [__meta_kubernetes_pod_ip]
        action: replace
        target_label: __address__
        replacement: ${1}:10259

  - job_name: 'etcd'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_component]
        action: keep
        regex: kube-system;etcd
      - source_labels: [__meta_kubernetes_pod_ip]
        action: replace
        target_label: __address__
        replacement: ${1}:2381
  {{- end }}
  {{- if .Values.coreDns.enabled }}
  - job_name: 'coredns'
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: kube-system;(coredns|kube-dns);metrics
  {{- end }}
  {{- if .Values.networkPlugin.calico.enabled }}
  - job_name: 'calico'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_k8s_app]
        action: keep
        regex: kube-system;calico-node
      - source_labels: [__meta_kubernetes_pod_ip]
        action: replace
        target_label: __address__
        replacement: ${1}:9091
  {{- end }}
  {{- if .Values.networkPlugin.cilium.enabled }}
  - job_name: 'cilium'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_app_kubernetes_io_name]
        action: keep
        regex: kube-system;cilium
      - source_labels: [__meta_kubernetes_pod_ip]
        action: replace
        target_label: __address__
        replacement: ${1}:9090
  {{- end }}
remote_write:
  - url: '{{ include "categraf.remoteWriteURL" . }}'
    basic_auth:
      username: "{{ .Values.categraf.remoteWriteUser }}"
      password: "{{ .Values.categraf.remoteWritePassword }}"
{{- end }}

{{- define "categraf.configChecksum" -}}
{{- printf "%s\n%s\n%s\n%s\n%s" .Chart.Version (.Values | toYaml) (include "categraf.nodeConfigToml" .) (include "categraf.ksmConfigToml" .) (include "categraf.ksmScrapeYaml" .) | sha256sum -}}
{{- end }}
