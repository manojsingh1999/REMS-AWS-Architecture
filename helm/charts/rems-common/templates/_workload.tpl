{{/* ================================================================ Deployment or Argo Rollout */}}
{{- define "rems-common.workload" -}}
{{- if .Values.rollout.enabled }}
apiVersion: argoproj.io/v1alpha1
kind: Rollout
{{- else }}
apiVersion: apps/v1
kind: Deployment
{{- end }}
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      {{- include "rems-common.selectorLabels" . | nindent 6 }}
  template:
    {{- include "rems-common.podTemplate" . | nindent 4 }}
  {{- if .Values.rollout.enabled }}
  strategy:
    canary:
      canaryService: {{ include "rems-common.fullname" . }}-canary
      stableService: {{ include "rems-common.fullname" . }}
      maxSurge: "25%"
      maxUnavailable: 0
      {{- if .Values.ingress.enabled }}
      trafficRouting:
        alb:
          ingress: {{ include "rems-common.fullname" . }}
          servicePort: {{ .Values.service.port }}
      {{- end }}
      {{- if .Values.rollout.analysis.enabled }}
      analysis:
        templates:
          {{- range .Values.rollout.analysis.templates }}
          - templateName: {{ . }}
            clusterScope: true
          {{- end }}
        startingStep: 1
        args:
          - name: service-name
            value: {{ include "rems-common.fullname" . }}
          - name: namespace
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
      {{- end }}
      steps:
        {{- toYaml .Values.rollout.steps | nindent 8 }}
  {{- else }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0
  {{- end }}
{{- end -}}

{{/* ================================================================ Background worker (same image, different entrypoint) */}}
{{- define "rems-common.worker" -}}
{{- if .Values.worker.enabled }}
{{- $name := printf "%s-worker" (include "rems-common.fullname" .) }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $name }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ $name }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ $name }}
        app.kubernetes.io/instance: {{ .Release.Name }}
        app.kubernetes.io/part-of: rems
        app.kubernetes.io/component: worker
    spec:
      serviceAccountName: {{ include "rems-common.serviceAccountName" . }}
      automountServiceAccountToken: false
      priorityClassName: rems-batch
      terminationGracePeriodSeconds: {{ .Values.worker.terminationGracePeriodSeconds }}
      enableServiceLinks: false
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      nodeSelector:
        rems.io/node-pool: workers
      tolerations:
        - key: rems.io/dedicated
          operator: Equal
          value: workers
          effect: NoSchedule
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: {{ $name }}
      containers:
        - name: worker
          image: {{ include "rems-common.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command:
            {{- toYaml (required "worker.command is required when worker.enabled" .Values.worker.command) | nindent 12 }}
          {{- with .Values.worker.args }}
          args:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          env:
            {{- include "rems-common.otelEnv" . | nindent 12 }}
          {{- $envFromSecrets := list }}
          {{- range .Values.externalSecrets }}{{- if .envFrom }}{{- $envFromSecrets = append $envFromSecrets .name }}{{- end }}{{- end }}
          {{- if or .Values.config $envFromSecrets }}
          envFrom:
            {{- if .Values.config }}
            - configMapRef:
                name: {{ include "rems-common.fullname" . }}
            {{- end }}
            {{- range $envFromSecrets }}
            - secretRef:
                name: {{ . }}
            {{- end }}
          {{- end }}
          resources:
            {{- toYaml .Values.worker.resources | nindent 12 }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            {{- range .Values.externalSecrets }}
            {{- if not .envFrom }}
            - name: secret-{{ .name }}
              mountPath: {{ printf "/var/run/secrets/rems/%s" .name }}
              readOnly: true
            {{- end }}
            {{- end }}
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: {{ .Values.tmpSizeLimit }}
        {{- range .Values.externalSecrets }}
        {{- if not .envFrom }}
        - name: secret-{{ .name }}
          secret:
            secretName: {{ .name }}
            defaultMode: 0440
        {{- end }}
        {{- end }}
---
# KEDA reads the Redis AUTH token from the ExternalSecret-managed Secret.
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: {{ $name }}-redis
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  secretTargetRef:
    - parameter: password
      name: {{ required "worker.redisAuthSecret is required" .Values.worker.redisAuthSecret }}
      key: auth_token
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ $name }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    name: {{ $name }}
  minReplicaCount: {{ .Values.worker.minReplicas }}
  maxReplicaCount: {{ .Values.worker.maxReplicas }}
  pollingInterval: 15
  cooldownPeriod: 300
  triggers:
    {{- toYaml .Values.worker.triggers | nindent 4 }}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $name }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  maxUnavailable: "50%"
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ $name }}
      app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- end -}}
