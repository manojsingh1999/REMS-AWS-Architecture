# Namespaces

**Status:** ✅ `kubernetes/base/namespaces.yaml`, `kubernetes/base/resource-governance.yaml`.

| Namespace | Contents | Pod Security | Notes |
|---|---|---|---|
| `rems` | frontend, rems-api, authorization-service, data-governance | restricted (enforce) | `elbv2.k8s.aws/pod-readiness-gate-inject: enabled` |
| `rems-ai` | metadata-rca, chat-engine, mcp-server, llm-gateway | restricted | Readiness gates |
| `observability` | OTel Collector, VictoriaMetrics, Loki, Tempo | – | Persistent volumes allowed |
| `monitoring` | kube-prometheus-stack (Prometheus, Alertmanager, Grafana) | – | – |
| `argocd`, `argo-rollouts`, `keda`, `kyverno`, `external-secrets`, `external-dns`, `amazon-cloudwatch` | Platform controllers | – | – |

## Real manifest (`kubernetes/base/namespaces.yaml`, first object)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rems
  labels:
    rems.io/tier: application
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    elbv2.k8s.aws/pod-readiness-gate-inject: enabled
```

## Quotas and defaults (`kubernetes/base/resource-governance.yaml`)

| Namespace | requests.cpu | requests.memory | pods | LoadBalancer / NodePort | PVCs |
|---|---|---|---|---|---|
| rems | 120 | 240Gi | 400 | 0 / 0 | 0 |
| rems-ai | 80 | 200Gi | 200 | 0 / 0 | – |

LimitRange `defaults` in `rems`: request 100m / 128Mi, default limit 1 CPU / 256Mi, max 4 CPU / 8Gi per container.

## Tenancy note

REMS tenants are **not** Kubernetes namespaces (pooled model). Tenant isolation happens in the application, database (RLS), cache keys and authorization layer. See [tenant isolation](../07-security/tenant-isolation.md). The silo option (dedicated namespace or cluster per regulated tenant) is 📋 planned only.

## Verification

```bash
kubectl get ns rems rems-ai -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}{end}'
kubectl describe quota -n rems
# PSS dry-run: a privileged pod must be rejected
kubectl run psscheck -n rems --image=public.ecr.aws/docker/library/busybox:1.36 --dry-run=server \
  --overrides='{"spec":{"containers":[{"name":"c","image":"public.ecr.aws/docker/library/busybox:1.36","securityContext":{"privileged":true}}]}}'
```

Expected: the last command fails with `violates PodSecurity "restricted:latest"`.

## Rollback

Namespaces are never deleted by rollback, because a delete would remove every workload in them. Revert label changes in Git.
