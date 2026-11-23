# Kubernetes Troubleshooting

## Triage commands

```bash
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl get events -n rems --sort-by=.lastTimestamp | tail -30
kubectl describe pod <pod> -n rems
kubectl logs <pod> -n rems --previous
kubectl top pods -n rems --sort-by=cpu
kubectl get applications -n argocd
kubectl argo rollouts get rollout <svc> -n rems
kubectl get externalsecrets -A
kubectl get nodeclaims
```

## Common failures

| Symptom | Cause | Resolution |
|---|---|---|
| `ImagePullBackOff` | Tag not in ECR, no ECR pull permission, or no ecr endpoints | `aws ecr describe-images --repository-name rems/<svc> --image-ids imageTag=<tag> --registry-id <shared-acct>`. Check the repository policy for the workload account |
| Kyverno `admission webhook denied` | Unsigned image, missing resources, root user | Read the policy message. Fix the chart/image, don't disable the policy |
| `CreateContainerConfigError: secret not found` | ExternalSecret not synced | `kubectl describe externalsecret <name> -n rems`. Check the Secrets Manager key name and the ESO Pod Identity role |
| Pod `Pending`, `exceeded quota` | ResourceQuota | `kubectl describe quota -n rems`. Raise it in `kubernetes/base/resource-governance.yaml` via PR |
| Pod `Pending`, no NodeClaim | NodePool limits or requirements don't match | `kubectl describe nodepool <pool>`. Check the toleration / nodeSelector `rems.io/node-pool` |
| `OOMKilled` | Memory limit too low | Raise `resources.limits.memory` in `values-<env>.yaml` |
| 5xx after a deploy | Bad version | Abort the rollout ([rollback](../06-cicd/rollback-procedure.md)) |
| ArgoCD `OutOfSync` loop | A field mutated by a controller (HPA replicas) | `ignoreDifferences` is configured for replicas. Check the Application spec |
| DNS failures | CoreDNS overloaded, or the `allow-dns` policy is missing | `kubectl -n kube-system get pods -l k8s-app=kube-dns`. Scale CoreDNS |
| Node `NotReady` in one AZ | AZ impairment | Follow `runbooks/az-failure.md` |

## Runbooks

Operational procedures live in [`runbooks/`](../../runbooks/README.md) (traffic spike, AZ failure, Redis failure, Postgres bottleneck, bad deployment, SLO burn, and more).
