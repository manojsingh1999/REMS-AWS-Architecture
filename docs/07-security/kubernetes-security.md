# Kubernetes Security

**Status:** ✅ Implemented across `kubernetes/base/`, `security/kyverno/`, `terraform/modules/eks`. ⚠️ Not applied.

| Area | Control | Where |
|---|---|---|
| API access | Private endpoint. Access entries (API mode). No cluster-creator admin | `terraform/modules/eks` |
| Authorization | ClusterRoles `rems-k8s-observer` (read-only for rems-api / mcp-server), `rems-oncall` | `kubernetes/base/rbac.yaml` |
| Admission | Pod Security Admission `restricted` on `rems`, `rems-ai`. Kyverno `Enforce` policies | `namespaces.yaml`, `security/kyverno/policies.yaml` |
| Network | Default-deny + allow-lists | [network policies](../04-kubernetes/network-policies.md) |
| Secrets | KMS envelope encryption. ESO with file mounts | [secrets](secrets-management.md) |
| Node | IMDSv2, hop limit 1. AL2023 AMI pinned via EC2NodeClass `amiSelectorTerms` alias (`al2023@v20241115` in prod) | `modules/eks`, overlays |
| Workload identity | Pod Identity, one role per SA | `identities.tf` |
| Audit | Control-plane audit logs → CloudWatch | `enabled_cluster_log_types` |
| GitOps | AppProject restrictions, ArgoCD SSO only | `cicd/argocd/` |
| Quotas | No LoadBalancer / NodePort Services, CPU/memory caps | `resource-governance.yaml` |

## Verification

```bash
kubectl auth can-i --list --as=system:serviceaccount:rems-ai:mcp-server
kubectl auth can-i delete pods -n rems --as=system:serviceaccount:rems:rems-api      # no
kubectl get --raw /api/v1/namespaces/rems | grep pod-security
aws logs filter-log-events --log-group-name /aws/eks/rems-prod/cluster \
  --filter-pattern '{ $.verb = "create" && $.objectRef.subresource = "exec" }' --max-items 10
```

## CIS EKS Benchmark

📋 Not yet run. After deploying, run `kube-bench run --benchmark eks-1.5.0` as a Job, or use Security Hub's EKS controls, and record the results here.

## Rollback

Every control is in Git. Revert through PR. Removing PSA labels or Kyverno policies needs a security approval (CODEOWNERS).
