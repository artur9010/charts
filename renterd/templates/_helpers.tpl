{{/*
Expand the name of the chart.
*/}}
{{- define "renterd.name" -}}
{{- default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "renterd.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "renterd.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "renterd.labels" -}}
helm.sh/chart: {{ include "renterd.chart" . }}
{{ include "renterd.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "renterd.selectorLabels" -}}
app.kubernetes.io/name: {{ include "renterd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "renterd.workerAddrs" -}}
    {{- $res := list -}}
    {{range $i, $e := until (int .Values.workers.replicas) }}
    {{- $res = append $res (printf "http://renterd-worker-%d.renterd-worker:%d/api/worker" (int $i) ( int $.Values.service.http.port )) -}}
    {{- end -}}
    {{- printf "%s" (join ";" $res) -}}
{{- end }}

{{- define "renterd.busAddr" -}}
    {{- printf "http://renterd-bus:%d/api/bus" (int .Values.service.http.port ) -}}
{{- end }}