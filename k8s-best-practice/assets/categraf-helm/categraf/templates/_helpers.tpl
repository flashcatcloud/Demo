{{- define "categraf.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "categraf.resourceName" -}}
{{- printf "%s-%s" .root.Release.Name .suffix | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "categraf.clusterResourceName" -}}
{{- $prefix := printf "%s-%s" .root.Release.Name .root.Release.Namespace -}}
{{- if .suffix -}}
{{- printf "%s-%s" $prefix .suffix | trunc 253 | trimSuffix "-" -}}
{{- else -}}
{{- $prefix | trunc 253 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{- define "categraf.valuesChecksum" -}}
{{- .Values | toYaml -}}
{{- end }}

{{- define "categraf.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "categraf.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "categraf.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "categraf.namespace" -}}
{{ .Release.Namespace }}
{{- end }}

{{- define "categraf.serverAddr" -}}
{{ .Values.categraf.serverAddr }}
{{- end }}

{{- define "categraf.heartbeatURL" -}}
{{ .Values.categraf.serverAddr }}/v1/n9e-plus/heartbeat{{- if .Values.categraf.heartbeatGid }}?gid={{ .Values.categraf.heartbeatGid }}{{ end }}
{{- end }}

{{- define "categraf.remoteWriteURL" -}}
{{ .Values.categraf.serverAddr }}/prometheus/v1/write
{{- end }}

{{- define "categraf.validateCustomLabels" -}}
{{- $reserved := list "cluster" "env" "categraf" -}}
{{- range $key, $value := . -}}
{{- $name := toString $key -}}
{{- if has $name $reserved -}}
{{- fail (printf "categraf.customLabels cannot override reserved label %q" $name) -}}
{{- end -}}
{{- if not (regexMatch "^[a-zA-Z_][a-zA-Z0-9_]*$" $name) -}}
{{- fail (printf "categraf.customLabels key %q is not a valid Prometheus label name" $name) -}}
{{- end -}}
{{- $kind := kindOf $value -}}
{{- if not (or (eq $kind "string") (eq $kind "bool") (eq $kind "int") (eq $kind "int64") (eq $kind "uint64") (eq $kind "float64")) -}}
{{- fail (printf "categraf.customLabels[%q] must be a string, number or boolean" $name) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "categraf.customLabelsToml" -}}
{{- include "categraf.validateCustomLabels" . -}}
{{- range $key, $value := . -}}
{{ $key | toString }} = {{ $value | toString | quote }}
{{ end }}
{{- end }}

{{- define "categraf.customLabelsYaml" -}}
{{- include "categraf.validateCustomLabels" . -}}
{{- range $key, $value := . -}}
{{ $key | toString }}: {{ $value | toString | quote }}
{{ end }}
{{- end }}

{{- define "categraf.validateRuntimeConfig" -}}
{{- $cfg := .Values.categraf -}}
{{- $interval := int (dig "config" "interval" 15 $cfg) -}}
{{- if le $interval 0 -}}
{{- fail "categraf.config.interval must be greater than 0" -}}
{{- end -}}
{{- $batch := int (dig "writer" "batch" 0 $cfg) -}}
{{- if lt $batch 0 -}}
{{- fail "categraf.writer.batch must be greater than or equal to 0" -}}
{{- end -}}
{{- $chanSize := int (dig "writer" "chanSize" 1000000 $cfg) -}}
{{- if le $chanSize 0 -}}
{{- fail "categraf.writer.chanSize must be greater than 0" -}}
{{- end -}}
{{- $heartbeatInterval := int (dig "heartbeat" "interval" 10 $cfg) -}}
{{- if le $heartbeatInterval 0 -}}
{{- fail "categraf.heartbeat.interval must be greater than 0" -}}
{{- end -}}
{{- $heartbeatTimeout := int (dig "heartbeat" "timeout" 5000 $cfg) -}}
{{- if le $heartbeatTimeout 0 -}}
{{- fail "categraf.heartbeat.timeout must be greater than 0" -}}
{{- end -}}
{{- $heartbeatDialTimeout := int (dig "heartbeat" "dialTimeout" 2500 $cfg) -}}
{{- if le $heartbeatDialTimeout 0 -}}
{{- fail "categraf.heartbeat.dialTimeout must be greater than 0" -}}
{{- end -}}
{{- end }}
