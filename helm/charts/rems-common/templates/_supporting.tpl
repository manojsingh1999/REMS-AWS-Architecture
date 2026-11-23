{{/* ================================================================ ServiceAccount (EKS Pod Identity binds by name) */}}
{{- define "rems-common.serviceAccount" -}}
{{- if .Values.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "rems-common.serviceAccountName" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
automountServiceAccountToken: false
{{- end }}
{{- end -}}

{{/* ================================================================ ConfigMap (non-secret config, PLACEHOLDER keys only) */}}
{{- define "rems-common.configMap" -}}
{{- if .Values.config }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
data:
  {{- range $k, $v := .Values.config }}
  {{ $k }}: {{ $v | quote }}
  {{- end }}
{{- end }}
{{- end -}}

{{/* ================================================================ ExternalSecrets (AWS Secrets Manager -> K8s Secret) */}}
{{- define "rems-common.externalSecrets" -}}
{{- range $i, $es := .Values.externalSecrets }}
{{- if $i }}
---
{{- end }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ $es.name }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" $ | nindent 4 }}
spec:
  refreshInterval: {{ $es.refreshInterval | default "1h" }}
  secretStoreRef:
    kind: ClusterSecretStore
    name: {{ $.Values.global.secretStore }}
  target:
    name: {{ $es.name }}
    creationPolicy: Owner
    deletionPolicy: Retain
  {{- if $es.keys }}
  data:
    {{- range $envName, $prop := $es.keys }}
    - secretKey: {{ $envName }}
      remoteRef:
        key: {{ $es.remoteKey }}
        property: {{ $prop }}
    {{- end }}
  {{- else }}
  dataFrom:
    - extract:
        key: {{ $es.remoteKey }}
  {{- end }}
{{- end }}
{{- end -}}

{{/* ================================================================ ServiceMonitor (Prometheus Operator) */}}
{{- define "rems-common.serviceMonitor" -}}
{{- if .Values.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      {{- include "rems-common.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: http
      path: {{ .Values.serviceMonitor.path }}
      interval: {{ .Values.serviceMonitor.interval }}
      scrapeTimeout: 10s
{{- end }}
{{- end -}}

{{/* ================================================================ Everything, in apply order */}}
{{- define "rems-common.all" -}}
{{- $docs := list
    (include "rems-common.serviceAccount" .)
    (include "rems-common.configMap" .)
    (include "rems-common.externalSecrets" .)
    (include "rems-common.service" .)
    (include "rems-common.workload" .)
    (include "rems-common.worker" .)
    (include "rems-common.autoscaling" .)
    (include "rems-common.pdb" .)
    (include "rems-common.networkPolicy" .)
    (include "rems-common.ingress" .)
    (include "rems-common.serviceMonitor" .)
-}}
{{- range $docs }}
{{- if trim . }}
---
{{ trim . }}
{{- end }}
{{- end }}
{{- end -}}
