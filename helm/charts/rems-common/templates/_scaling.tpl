{{/* ================================================================ HPA (CPU/memory) or KEDA ScaledObject (event driven) */}}
{{- define "rems-common.autoscaling" -}}
{{- if .Values.autoscaling.enabled }}
{{- $target := dict "apiVersion" (ternary "argoproj.io/v1alpha1" "apps/v1" .Values.rollout.enabled) "kind" (ternary "Rollout" "Deployment" .Values.rollout.enabled) "name" (include "rems-common.fullname" .) }}
{{- if eq .Values.autoscaling.type "keda" }}
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: {{ $target.apiVersion }}
    kind: {{ $target.kind }}
    name: {{ $target.name }}
  minReplicaCount: {{ .Values.autoscaling.minReplicas }}
  maxReplicaCount: {{ .Values.autoscaling.maxReplicas }}
  pollingInterval: 15
  cooldownPeriod: 300
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        {{- toYaml .Values.autoscaling.behavior | nindent 8 }}
  triggers:
    - type: cpu
      metricType: Utilization
      metadata:
        value: {{ .Values.autoscaling.targetCPUUtilizationPercentage | quote }}
    {{- with .Values.autoscaling.keda.triggers }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- else }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: {{ $target.apiVersion }}
    kind: {{ $target.kind }}
    name: {{ $target.name }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
    {{- if .Values.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
  behavior:
    {{- toYaml .Values.autoscaling.behavior | nindent 4 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ================================================================ PodDisruptionBudget */}}
{{- define "rems-common.pdb" -}}
{{- if .Values.pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  {{- if hasKey .Values.pdb "minAvailable" }}
  minAvailable: {{ .Values.pdb.minAvailable }}
  {{- else }}
  maxUnavailable: {{ .Values.pdb.maxUnavailable | default 1 }}
  {{- end }}
  unhealthyPodEvictionPolicy: AlwaysAllow
  selector:
    matchLabels:
      {{- include "rems-common.selectorLabels" . | nindent 6 }}
{{- end }}
{{- end -}}
