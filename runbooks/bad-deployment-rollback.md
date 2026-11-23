# Runbook: A Kubernetes deployment introduces a production regression

**Alerts:** `RemsRolloutAborted`, `RemsPodCrashLooping`, SLO burn right after a sync (ArgoCD notification `on-deployed` in `#rems-deployments`).

## Automatic protection

* **Canary**: 10 % → 25 % → 50 % → 100 % with pauses. At every step, the `rems-http-error-rate` (< 1 % 5xx) and `rems-http-latency-p95` (< 500 ms) ClusterAnalysisTemplates run. A failed analysis **aborts the rollout** and sends 100 % of traffic back to the stable ReplicaSet (ALB weights reset) in under a minute.
* Readiness gates and probes keep broken pods out of the ALB. `maxUnavailable: 0` means stable capacity never drops.

## If the regression passed the canary (logic bug, slow leak)

| Option | Command | Time |
|---|---|---|
| Rollback via Git (preferred, audited) | `gh workflow run rollback.yml -R your-github-org/rems-microconfig -f service=rems-api -f environment=prod -f reason="INC-1234"` (opens a labelled PR) | 2–4 min |
| Revert the promotion PR | `git revert <merge-sha>` → PR → merge | 5–10 min |
| Break-glass (on-call role) | `kubectl argo rollouts undo rems-api -n rems`, then **also** revert Git, because ArgoCD self-heal would otherwise reapply the bad version | < 1 min |
| Abort an in-flight rollout | `kubectl argo rollouts abort rems-api -n rems` | seconds |

## Database migrations

Releases follow **expand/contract**: new columns and tables are added in release N, code switches in N+1, and old columns are dropped in N+2. An application rollback therefore never needs a schema rollback. If a migration itself is the cause, follow [postgres-restore.md](postgres-restore.md) for a partial PITR restore.

## Afterwards

* Write a blameless postmortem. Add a regression test and, if the canary missed it, a new analysis metric (for example, a business KPI or a specific route's error rate).
* Error-budget policy: if the budget is exhausted, freeze features for the service.
