{{/* ================================================================ Services (stable + canary) */}}
{{- define "rems-common.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "rems-common.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
{{- if .Values.rollout.enabled }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "rems-common.fullname" . }}-canary
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "rems-common.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
{{- end }}
{{- end -}}

{{/* ================================================================ Ingress (AWS Load Balancer Controller) */}}
{{- define "rems-common.ingress" -}}
{{- if .Values.ingress.enabled }}
{{- $g := .Values.global.ingress }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
  annotations:
    alb.ingress.kubernetes.io/group.name: {{ .Values.ingress.groupName | default (ternary $g.publicGroup $g.internalGroup (eq .Values.ingress.scheme "internet-facing")) }}
    alb.ingress.kubernetes.io/group.order: {{ .Values.ingress.order | quote }}
    alb.ingress.kubernetes.io/scheme: {{ .Values.ingress.scheme }}
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
    alb.ingress.kubernetes.io/certificate-arn: {{ $g.certificateArn | quote }}
    alb.ingress.kubernetes.io/healthcheck-path: {{ .Values.probes.readiness.path }}
    alb.ingress.kubernetes.io/success-codes: "200-299"
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "10"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
    alb.ingress.kubernetes.io/unhealthy-threshold-count: "2"
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30,load_balancing.algorithm.type=least_outstanding_requests
    alb.ingress.kubernetes.io/load-balancer-attributes: {{ printf "idle_timeout.timeout_seconds=%v,routing.http.drop_invalid_header_fields.enabled=true,access_logs.s3.enabled=true,access_logs.s3.bucket=%s,access_logs.s3.prefix=alb,deletion_protection.enabled=%v" .Values.ingress.idleTimeoutSeconds $g.accessLogsBucket $g.deletionProtection }}
    {{- if eq .Values.ingress.scheme "internet-facing" }}
    alb.ingress.kubernetes.io/wafv2-acl-arn: {{ $g.wafAclArn | quote }}
    {{- end }}
    {{- with .Values.ingress.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  ingressClassName: alb
  rules:
    - host: {{ required "ingress.host is required" .Values.ingress.host | quote }}
      http:
        paths:
          {{- range .Values.ingress.paths }}
          - path: {{ . }}
            pathType: Prefix
            backend:
              service:
                name: {{ include "rems-common.fullname" $ }}
                port:
                  {{- if $.Values.rollout.enabled }}
                  name: use-annotation
                  {{- else }}
                  number: {{ $.Values.service.port }}
                  {{- end }}
          {{- end }}
{{- end }}
{{- end -}}

{{/* ================================================================ NetworkPolicy (per service allow-list) */}}
{{- define "rems-common.networkPolicy" -}}
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "rems-common.fullname" . }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "rems-common.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "rems-common.selectorLabels" . | nindent 6 }}
  policyTypes: [Ingress, Egress]
  ingress:
    {{- if .Values.ingress.enabled }}
    # ALB (target-type ip) connects from VPC addresses.
    - from:
        - ipBlock:
            cidr: {{ .Values.global.vpcCidr }}
      ports:
        - protocol: TCP
          port: {{ .Values.containerPort }}
    {{- end }}
    {{- range .Values.networkPolicy.ingressFrom }}
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .namespace }}
          podSelector:
            matchLabels:
              app.kubernetes.io/name: {{ .app }}
      ports:
        - protocol: TCP
          port: {{ $.Values.containerPort }}
    {{- end }}
    {{- if not (or .Values.ingress.enabled .Values.networkPolicy.ingressFrom) }}
    []
    {{- end }}
  egress:
    {{- range .Values.networkPolicy.egressTo }}
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .namespace }}
          {{- if .app }}
          podSelector:
            matchLabels:
              app.kubernetes.io/name: {{ .app }}
          {{- end }}
      {{- with .ports }}
      ports:
        {{- range . }}
        - protocol: TCP
          port: {{ . }}
        {{- end }}
      {{- end }}
    {{- end }}
    {{- range .Values.networkPolicy.egressCIDRs }}
    - to:
        - ipBlock:
            cidr: {{ .cidr }}
      ports:
        {{- range .ports }}
        - protocol: TCP
          port: {{ . }}
        {{- end }}
    {{- end }}
    {{- if .Values.networkPolicy.allowKubeAPI }}
    - to:
        - ipBlock:
            cidr: {{ .Values.global.vpcCidr }}
      ports:
        - protocol: TCP
          port: 443
    {{- end }}
{{- end }}
{{- end -}}
