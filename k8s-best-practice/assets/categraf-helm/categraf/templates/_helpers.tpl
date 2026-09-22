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
