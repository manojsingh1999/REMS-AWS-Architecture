# Dashboards

**Status:** ✅ Three dashboards provisioned as ConfigMaps in `monitoring/grafana/dashboards/dashboards.yaml`. ⚠️ Panels reference metric names that exist only once services are OTel-instrumented.

| ConfigMap | Dashboard | Content |
|---|---|---|
| `grafana-dashboard-rems-slo-overview` | REMS SLO overview | Availability and latency SLIs, remaining error budget, burn rates per service |
| `grafana-dashboard-rems-service-red` | Service RED | Rate, errors, duration per service (from `http_server_request_duration_seconds`) |
| `grafana-dashboard-rems-ai-gateway` | AI gateway | LLM requests, errors by provider, latency, tokens, spend per tenant |

Also available from the add-on charts: Kubernetes / node dashboards (kube-prometheus-stack), Karpenter, ArgoCD, Argo Rollouts, plus CloudWatch Container Insights and Aurora Performance Insights in the AWS console.

## Add a dashboard

1. Build it in Grafana (dev), then export the JSON.
2. Add a ConfigMap labelled `grafana_dashboard: '1'` with the annotation `grafana_folder: REMS`.
3. `./scripts/validate.sh k8s` → PR → ArgoCD.

## Verification

```bash
kubectl -n monitoring get configmap -l grafana_dashboard=1 -o name
```

The label `grafana_dashboard: '1'` and annotation `grafana_folder: REMS` come from `dashboards.yaml`. The sidecar settings are in `kube-prometheus-stack/values.yaml`.

## Rollback

Revert the ConfigMap.
