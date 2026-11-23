# REMS Helm charts

```
helm/
  charts/
    rems-common/            library chart: hardened Deployment/Rollout, Service(+canary), Ingress (ALB), HPA/KEDA,
                            PDB, NetworkPolicy, ServiceAccount, ConfigMap, ExternalSecret, ServiceMonitor, worker
    rems-frontend/          React/Vite SPA (nginx)           namespace rems
    rems-api/               FastAPI backend (+ optional worker) namespace rems
    authorization-service/  RBAC / policy / audit            namespace rems
    data-governance/        DB scanning / governance          namespace rems
    metadata-rca/           RCA / SOP / RAG (Savvy)           namespace rems-ai
    chat-engine/            AI chat analysis                  namespace rems-ai
    mcp-server/             MCP tools (internal ALB)          namespace rems-ai
  environments/<env>/global.yaml   values shared by all charts in an environment (from terraform outputs)
```

Every service chart is a thin wrapper: `templates/resources.yaml` includes `rems-common.all`, and all behaviour is driven by `values.yaml`.
That keeps security and reliability defaults in one place (non-root, read-only root FS, seccomp, dropped capabilities,
topology spread, PDB, preStop drain, probes, Pod Identity service account, default-deny networking).

## Values layering (same order ArgoCD uses)

1. `charts/<svc>/values.yaml` holds defaults. Every key is documented inline.
2. `charts/<svc>/values-<env>.yaml` holds the image tag (written by CI), replicas, secrets paths and egress CIDRs.
3. `environments/<env>/global.yaml` holds the region, VPC CIDR, ACM/WAF ARNs and the ALB log bucket.

## Commands

```bash
helm dependency build helm/charts/rems-api
helm lint helm/charts/rems-api -f helm/charts/rems-api/values-prod.yaml -f helm/environments/prod/global.yaml
helm template rems-api helm/charts/rems-api -n rems \
  -f helm/charts/rems-api/values-prod.yaml -f helm/environments/prod/global.yaml | kubeconform -strict -summary

# Offline (no helm binary): renders all 7 charts x 3 environments and runs kubeconform
python3 scripts/helm_render_check.py --out /tmp/rendered
```

## Progressive delivery

`rollout.enabled: true` (staging and prod) swaps the Deployment for an Argo Rollout:
canary at 10 → 25 → 50 → 100 %, with ALB weighted target groups for public services and replica-weighted
canaries for internal ones. `ClusterAnalysisTemplate`s (`cicd/argo-rollouts/`) evaluate the 5xx ratio and p95 latency from Prometheus,
and a failed analysis aborts the rollout automatically.
