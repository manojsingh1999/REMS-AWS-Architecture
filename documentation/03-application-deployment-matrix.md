# Application Deployment Matrix

Production values. Dev and staging use the same charts with `values-dev.yaml` / `values-staging.yaml` (smaller requests, 1–2 replicas, Spot).
Resource requests are **starting points** derived from assumption A5. Re-baseline them with k6 and VPA recommendation mode before go-live.

| Component | K8s kind / delivery | Namespace / node pool | Replicas min–max (prod) | CPU req / limit | Mem req = limit | Autoscaling trigger | PDB | Priority | Exposure |
|---|---|---|---|---|---|---|---|---|---|
| rems-frontend | Rollout (canary) | `rems` / general | 3–10 | 100m / 500m | 256Mi | HPA CPU 70 % | minAvailable 2 | rems-high | public ALB `/` |
| rems-api | Rollout (canary) | `rems` / general | 6–40 | 500m / 2 | 1Gi | KEDA: RPS per pod > 80 **or** CPU 65 % | maxUnavailable 1 | rems-critical | public ALB `/api` |
| rems-api-worker | Deployment | `rems` / workers (Spot) | 3–60 | 250m / 1 | 512Mi | KEDA: Redis list length > 500 per pod | maxUnavailable 50 % | rems-batch | none |
| authorization-service | Rollout | `rems` / general | 3–20 | 250m / 1 | 512Mi | HPA CPU 60 % | minAvailable 2 | rems-critical | ClusterIP only |
| data-governance | Rollout | `rems` / general | 2–10 | 500m / 2 | 1Gi | HPA CPU 70 % | minAvailable 1 | rems-high | ClusterIP (admin via API) |
| metadata-rca (Savvy) | Rollout | `rems-ai` / ai | 2–12 | 1 / 2 | 2Gi | KEDA: in-flight requests per pod > 10, CPU 70 % | minAvailable 1 | rems-high | ClusterIP (via API/chat) |
| chat-engine | Rollout | `rems-ai` / ai | 3–20 | 500m / 2 | 1Gi | KEDA: in-flight requests per pod > 20 | minAvailable 2 | rems-high | public ALB `/chat` (SSE) |
| mcp-server | Rollout | `rems-ai` / general | 2–10 | 250m / 1 | 512Mi | HPA CPU 60 % | minAvailable 1 | rems-high | internal ALB `/mcp` |
| llm-gateway (LiteLLM) | Deployment | `rems-ai` / ai | 3–12 | 500m / 2 | 1Gi | HPA CPU 60 % | minAvailable 2 | rems-high | ClusterIP |
| otel-collector gateway | Deployment | `observability` | 3–30 | 500m / 2 | 1Gi | HPA CPU 60 % / memory 70 % | minAvailable 2 | rems-high | public ALB `/otlp` (API-key auth) |
| VictoriaMetrics cluster | StatefulSets | `observability` | insert 3–9, select 3–6, storage 3 | 1–2 cores | 4–8Gi | HPA (insert/select) | maxUnavailable 1 | rems-high | internal |
| Loki (simple scalable) | StatefulSet + Deployments | `observability` | write 3–12, read 3–9, backend 3 | 1 | 2–4Gi | HPA | maxUnavailable 1 | rems-high | internal |
| Tempo (distributed) | Deployments/StatefulSets | `observability` | distributor 3–9, ingester 3, querier 2–6 | 500m–1 | 2–4Gi | HPA | maxUnavailable 1 | rems-high | internal |
| kube-prometheus-stack | StatefulSet (Prometheus HA ×2) | `monitoring` | 2 | 1 | 6Gi | – | – | system | internal |

**Common to all REMS services:** `runAsNonRoot`, read-only root FS, `seccompProfile: RuntimeDefault`, drop ALL capabilities, topology spread across zones and hosts, `terminationGracePeriodSeconds: 45`, `preStop` sleep 15 s, startup/liveness/readiness probes, ServiceMonitor, OTel env vars, dedicated ServiceAccount with Pod Identity, NetworkPolicy, ExternalSecret.

**AZ-failure sizing rule:** `minReplicas ≥ ceil(peak_pods_needed × 3/2)` so two AZs can absorb the peak at the target utilization.
