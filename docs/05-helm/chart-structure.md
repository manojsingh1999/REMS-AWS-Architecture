# Chart Structure

**Status:** ✅ 1 library chart + 7 service charts. All 28 combinations (7 charts × 4 environments) render and pass kubeconform strict.

```text
helm/
├── charts/
│   ├── rems-common/                  # type: library, version 1.0.0
│   │   └── templates/
│   │       ├── _helpers.tpl          # names, labels, image ref (tag or digest)
│   │       ├── _workload.tpl         # Deployment or Rollout (+ optional worker), pod spec hardening
│   │       ├── _networking.tpl       # Service (+canary), Ingress (ALB), NetworkPolicy
│   │       ├── _scaling.tpl          # HPA or KEDA ScaledObject, PDB
│   │       └── _supporting.tpl       # ServiceAccount, ConfigMap, ExternalSecret, ServiceMonitor, rems-common.all
│   ├── rems-frontend/ rems-api/ authorization-service/ data-governance/
│   ├── metadata-rca/ chat-engine/ mcp-server/
│   │   ├── Chart.yaml                # depends on rems-common 1.0.0 (file://../rems-common)
│   │   ├── templates/resources.yaml  # {{ include "rems-common.all" . }}
│   │   ├── values.yaml               # defaults, every key commented
│   │   └── values-{dev,staging,prod,prod-dr}.yaml   # seed copies of the per-env values
└── environments/{dev,staging,prod,prod-dr}/global.yaml
```

## Why a library chart

Every service gets the same security and reliability defaults (non-root, read-only FS, seccomp, drop ALL capabilities, topology spread, PDB, preStop drain, default-deny networking) from one place. A fix in `rems-common` reaches all 7 services through one version bump.

## Real chart files (rems-api)

`helm/charts/rems-api/Chart.yaml`:

```yaml
apiVersion: v2
name: rems-api
description: REMS FastAPI backend (PostgreSQL, VictoriaMetrics/Prometheus, Loki, Tempo, Kubernetes integrations)
type: application
version: 1.0.0
appVersion: 0.0.0-placeholder
kubeVersion: '>=1.29.0-0'
dependencies:
- name: rems-common
  version: 1.0.0
  repository: file://../rems-common
annotations:
  rems.io/namespace: rems
```

`helm/charts/rems-api/templates/resources.yaml`:

```yaml
{{- /* All objects come from the rems-common library chart; see values.yaml */ -}}
{{ include "rems-common.all" . }}
```

## Objects rendered per chart (prod)

| Chart | Objects |
|---|---|
| rems-api | ServiceAccount, 2× ExternalSecret, 2× Service, Rollout, ScaledObject, PDB, NetworkPolicy, Ingress, ServiceMonitor |
| rems-frontend | ServiceAccount, 2× Service, Rollout, HPA, PDB, NetworkPolicy, Ingress |
| others | Same pattern. Ingress only for chat-engine (public) and mcp-server (internal) |

Generate the full list yourself:

```bash
python3 scripts/helm_render_check.py --out /tmp/rendered
grep -h '^kind:' /tmp/rendered/prod/*.yaml | sort | uniq -c
```

## Third-party charts

| Component | Chart | Values in repo |
|---|---|---|
| LLM gateway | LiteLLM | `ai-infrastructure/llm-gateway/values.yaml` |
| ArgoCD | argo/argo-cd 7.7.10 | `cicd/argocd/install/values.yaml` |
| Add-ons | see `cicd/argocd/apps/<env>/platform-addons.yaml` | `kubernetes/platform-addons/*/values*.yaml` |
| Observability | kube-prometheus-stack, loki, tempo, opentelemetry-collector, victoria-metrics | `monitoring/*/values.yaml` |
