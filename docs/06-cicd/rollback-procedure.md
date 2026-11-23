# Rollback Procedure

**Status:** ✅ Automatic (Argo Rollouts analysis abort), GitOps (`rollback.yml` in microconfig) and manual commands documented in `runbooks/bad-deployment-rollback.md`. ⚠️ Not exercised.

## Decision table

| Situation | Action | Time to effect |
|---|---|---|
| Canary in progress, analysis fails | Automatic abort. Traffic returns to stable | ~1 analysis interval |
| Canary in progress, humans see a problem | `kubectl argo rollouts abort` | seconds |
| Fully promoted bad release | `rollback.yml` (GitOps revert to the previous tag) | ArgoCD sync (~3 min) |
| ArgoCD or GitHub unavailable | `kubectl argo rollouts undo` + disable auto-sync | seconds |
| Bad DB migration | Not a deploy rollback. Use [backup & restore](../08-database/backup-and-restore.md) | minutes to hours |

## Steps

### 1. Abort an in-flight canary

```bash
kubectl argo rollouts get rollout rems-api -n rems
kubectl argo rollouts abort rems-api -n rems
kubectl argo rollouts status rems-api -n rems    # Degraded (aborted) = stable still serving
```

### 2. GitOps rollback (permanent, audited)

```bash
gh workflow run rollback.yml -R <org>/rems-microconfig \
  -f service=rems-api -f environment=prod -f reason="INC-<number>: <summary>"
gh pr list -R <org>/rems-microconfig --label rollback
```

Approve and merge the PR. ArgoCD syncs the previous tag. Then `kubectl argo rollouts retry rollout rems-api -n rems` if the rollout stays aborted.

### 3. Break-glass (Git path unavailable)

```bash
argocd app set rems-prod-rems-api --sync-policy none      # stop ArgoCD reverting you
kubectl argo rollouts undo rems-api -n rems               # previous ReplicaSet
# Afterwards: make Git match the cluster, then re-enable auto-sync:
argocd app set rems-prod-rems-api --sync-policy automated --self-heal --auto-prune
```

## Verification

```bash
kubectl argo rollouts get rollout rems-api -n rems   # stable image = previous tag
./scripts/smoke-test.sh https://<host> rems-prod
```

Check the SLO dashboard: error rate and p95 latency back within target.

## Security considerations

Rollbacks go through the same reviewed PR path. Break-glass actions are logged in the EKS audit log. Record them in the incident.

## Rollback of the rollback

Promote the fixed tag through the normal `promote.yml` path.
