{{/* ================================================================ names */}}
{{- define "rems-common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fullname deliberately equals the chart name (not release-prefixed) so the
     ServiceAccount matches the EKS Pod Identity association created by Terraform. */}}
{{- define "rems-common.fullname" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rems-common.serviceAccountName" -}}
{{- default (include "rems-common.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{- define "rems-common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rems-common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rems-common.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "rems-common.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/component: {{ .Values.component | quote }}
app.kubernetes.io/part-of: rems
app.kubernetes.io/managed-by: {{ .Release.Service }}
rems.io/environment: {{ .Values.global.environment | quote }}
{{- end -}}

{{/* ================================================================ image */}}
{{- define "rems-common.image" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repo (required "image.tag is required (set by CI, e.g. sha-<commit>)" .Values.image.tag) -}}
{{- end -}}
{{- end -}}

{{/* ================================================================ OpenTelemetry (standard OTEL_* variables only) */}}
{{- define "rems-common.otelEnv" -}}
{{- if .Values.otel.enabled }}
- name: OTEL_SERVICE_NAME
  value: {{ include "rems-common.fullname" . | quote }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ .Values.otel.endpoint | quote }}
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: {{ .Values.otel.protocol | quote }}
- name: OTEL_TRACES_SAMPLER
  value: parentbased_traceidratio
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ .Values.otel.samplerRatio | quote }}
- name: K8S_POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: K8S_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: OTEL_RESOURCE_ATTRIBUTES
  value: {{ printf "deployment.environment=%s,service.namespace=rems,k8s.pod.name=$(K8S_POD_NAME),k8s.node.name=$(K8S_NODE_NAME),service.version=%s" .Values.global.environment (.Values.image.tag | default "unknown") | quote }}
{{- end }}
- name: AWS_REGION
  value: {{ .Values.global.awsRegion | quote }}
{{- range $k, $v := .Values.extraEnv }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/* ================================================================ scheduling */}}
{{- define "rems-common.scheduling" -}}
{{- if .Values.nodePool }}
nodeSelector:
  rems.io/node-pool: {{ .Values.nodePool }}
{{- end }}
tolerations:
  # Evict from failed nodes after 60 s instead of the default 300 s (faster AZ-failure recovery).
  - key: node.kubernetes.io/not-ready
    operator: Exists
    effect: NoExecute
    tolerationSeconds: {{ .Values.nodeFailureTolerationSeconds | default 60 }}
  - key: node.kubernetes.io/unreachable
    operator: Exists
    effect: NoExecute
    tolerationSeconds: {{ .Values.nodeFailureTolerationSeconds | default 60 }}
  {{- if has .Values.nodePool (list "ai" "observability" "workers") }}
  - key: rems.io/dedicated
    operator: Equal
    value: {{ .Values.nodePool }}
    effect: NoSchedule
  {{- end }}
{{- if .Values.topologySpread.enabled }}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: {{ .Values.topologySpread.zoneWhenUnsatisfiable }}
    labelSelector:
      matchLabels:
        {{- include "rems-common.selectorLabels" . | nindent 8 }}
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        {{- include "rems-common.selectorLabels" . | nindent 8 }}
{{- end }}
{{- end -}}

{{/* ================================================================ pod spec (shared by Deployment and Rollout) */}}
{{- define "rems-common.podTemplate" -}}
metadata:
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    checksum/config: {{ toJson .Values.config | sha256sum }}
    {{- with .Values.podAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  serviceAccountName: {{ include "rems-common.serviceAccountName" . }}
  automountServiceAccountToken: {{ .Values.serviceAccount.automountToken }}
  priorityClassName: {{ .Values.priorityClassName }}
  terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
  enableServiceLinks: false
  securityContext:
    {{- toYaml .Values.podSecurityContext | nindent 4 }}
  {{- include "rems-common.scheduling" . | nindent 2 }}
  containers:
    - name: {{ include "rems-common.name" . }}
      image: {{ include "rems-common.image" . }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      {{- with .Values.command }}
      command:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.args }}
      args:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      ports:
        - name: http
          containerPort: {{ required "containerPort is required (from the service Dockerfile)" .Values.containerPort }}
          protocol: TCP
      env:
        {{- include "rems-common.otelEnv" . | nindent 8 }}
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
      {{- with .Values.probes.startup }}
      startupProbe:
        httpGet:
          path: {{ .path }}
          port: http
        periodSeconds: {{ .periodSeconds }}
        failureThreshold: {{ .failureThreshold }}
      {{- end }}
      {{- with .Values.probes.liveness }}
      livenessProbe:
        httpGet:
          path: {{ .path }}
          port: http
        periodSeconds: {{ .periodSeconds }}
        timeoutSeconds: {{ .timeoutSeconds }}
        failureThreshold: {{ .failureThreshold }}
      {{- end }}
      {{- with .Values.probes.readiness }}
      readinessProbe:
        httpGet:
          path: {{ .path }}
          port: http
        periodSeconds: {{ .periodSeconds }}
        timeoutSeconds: {{ .timeoutSeconds }}
        failureThreshold: {{ .failureThreshold }}
      {{- end }}
      lifecycle:
        preStop:
          # Let the ALB deregister the target before the process receives SIGTERM.
          sleep:
            seconds: {{ .Values.preStopSleepSeconds }}
      resources:
        {{- toYaml .Values.resources | nindent 8 }}
      securityContext:
        {{- toYaml .Values.securityContext | nindent 8 }}
      volumeMounts:
        - name: tmp
          mountPath: /tmp
        # Secret keys are files: /var/run/secrets/rems/<secret>/<json-key> (no env var names are assumed)
        {{- range .Values.externalSecrets }}
        {{- if not .envFrom }}
        - name: secret-{{ .name }}
          mountPath: {{ printf "/var/run/secrets/rems/%s" .name }}
          readOnly: true
        {{- end }}
        {{- end }}
        {{- with .Values.extraVolumeMounts }}
        {{- toYaml . | nindent 8 }}
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
    {{- with .Values.extraVolumes }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end -}}
