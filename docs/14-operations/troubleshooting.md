# Operational Troubleshooting (index)

Start at the symptom, then follow the link.

| Symptom | First command | Go to |
|---|---|---|
| Users see 5xx | `kubectl argo rollouts list rollouts -n rems` · ALB 5xx metrics | [rollback](../06-cicd/rollback-procedure.md), `runbooks/slo-burn-rate.md` |
| Latency up, CPU fine | Aurora Performance Insights top SQL | `runbooks/postgres-bottleneck.md`, [pooling](../08-database/connection-pooling.md) |
| Pods Pending | `kubectl get nodeclaims; kubectl describe pod <p>` | [autoscaling](../04-kubernetes/autoscaling.md) |
| Pods CrashLoopBackOff | `kubectl logs <p> --previous` | [K8s troubleshooting](../04-kubernetes/troubleshooting.md) |
| Deploy blocked by admission | `kubectl get events -n rems` (Kyverno message) | [container security](../07-security/container-security.md) |
| Secrets not mounting | `kubectl describe externalsecret <n> -n <ns>` | [secrets](../07-security/secrets-management.md) |
| ArgoCD OutOfSync / Degraded | `argocd app get <app>` | [ArgoCD](../06-cicd/argocd-setup.md) |
| Chat / RCA errors | Gateway dashboard, `RemsLLM*` alerts | `runbooks/ai-provider-outage.md` |
| Redis errors | `aws elasticache describe-events --duration 60` | `runbooks/redis-failure.md` |
| One AZ unhealthy | `kubectl get nodes -L topology.kubernetes.io/zone` | `runbooks/az-failure.md` |
| Telemetry bill jump | `RemsTenantLogVolumeSpike` | `runbooks/telemetry-cost-spike.md` |
| Suspicious cross-tenant access | Audit log `/rems/<env>/audit` | `runbooks/cross-tenant-access-attempt.md` |
| MCP tool misuse | `RemsMCPDeniedToolCalls` | `runbooks/compromised-mcp-tool.md` |
| Terraform errors | – | [Terraform troubleshooting](../03-terraform/troubleshooting.md) |
| Region down | – | [recovery runbook](../11-ha-dr/recovery-runbook.md) |
