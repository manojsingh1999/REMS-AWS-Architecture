# Runbook: REMS API traffic increases 10× within 5 minutes

**Alerts:** `RemsAutoscalerAtMax`, `RemsPendingPodsTooLong`, `RemsKarpenterNodePoolNearLimit`, SLO latency burn on `rems-api`.

## Automatic response timeline

| t | Mechanism |
|---|---|
| 0–15 s | Overprovisioning pause pods (priority -10) are preempted, so API pods land on warm nodes immediately |
| 15–45 s | KEDA (RPS per pod > 80, 15 s polling) and the HPA behaviour (+100 % or +4 pods every 15 s) scale `rems-api` from 6 toward 40 |
| 45–90 s | Karpenter provisions nodes for the remaining pending pods. Graviton/Spot diversified, usually ready in under 60 s |
| continuous | WAF per-IP rate limit (6 000 / 5 min) blocks single-source floods. Authz decision caching in Redis absorbs the extra authorization load |
| DB tier | RDS Proxy queues connections (borrow timeout 30 s) instead of overloading Postgres. Readers auto scale on CPU > 60 % (2 → 5, about 10 min) |

## Diagnose

1. **Legitimate or abusive?** In WAF sampled requests and the ALB logs, check the top IPs, user agents and tenants. In Grafana, check RPS by route and tenant.
2. **Where is the ceiling?**
   * HPA at max (`kubectl get hpa,scaledobject -n rems`)
   * Pending pods (quota or NodePool limits)
   * Aurora (connections, CPU)
   * Redis CPU
   * The LLM gateway, if traffic is chat
3. Check the error-budget burn on `REMS / SLO overview`.

## Actions

| Situation | Action |
|---|---|
| Abusive traffic | Add an IP set or rate-based rule scoped to the path or tenant in WAF (Terraform PR, or console break-glass with a follow-up PR) |
| HPA pinned at max, nodes available | Raise `autoscaling.maxReplicas` in `values-prod.yaml` (PR, fast-track approval) |
| Karpenter limit reached | Raise the NodePool `limits.cpu` in `kubernetes/overlays/prod` (PR) |
| Aurora writer saturated | Follow [postgres-bottleneck.md](postgres-bottleneck.md) |
| Single tenant | Apply a tenant rate limit (authz policy and gateway), and contact the account owner |

## Afterwards

Feed the observed peak into `documentation/05-capacity-plan.md`. Re-run `spike-10x.js` in staging at the new peak, and adjust `minReplicas` and the overprovisioning replicas.
