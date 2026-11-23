# Application Deployment with Helm + ArgoCD

**Status:** ✅ ApplicationSets (`cicd/argocd/apps/<env>/rems-services.yaml` and the Terraform equivalent in `terraform/cicd/argocd/apps.tf`). ⚠️ Not synced to a real cluster.

## Objective

Deploy the 7 REMS services in dependency order, with values from rems-microconfig and no manual `helm install`.

## Prerequisites

* ArgoCD installed ([ArgoCD setup](../06-cicd/argocd-setup.md)) and the platform layer healthy (waves -40 … 0).
* Secrets present in Secrets Manager. DB roles bootstrapped ([PostgreSQL setup](../08-database/postgresql-setup.md)).
* Images in ECR for the tags referenced in `apps/<svc>/values-<env>.yaml`.

## Sync order (ApplicationSet list generator)

| Wave | Service | Namespace |
|---|---|---|
| 1 | authorization-service | rems |
| 2 | rems-api, data-governance, metadata-rca | rems / rems-ai |
| 3 | mcp-server, chat-engine | rems-ai |
| 4 | rems-frontend | rems |

## Real ApplicationSet source block (`cicd/argocd/apps/prod/rems-services.yaml`)

```yaml
      sources:
        - repoURL: https://github.com/your-github-org/REMS-AWS-Architecture.git   # PLACEHOLDER org/repo
          targetRevision: main
          path: "helm/charts/{{.service}}"
          helm:
            releaseName: "{{.service}}"
            valueFiles:
              - $values/apps/{{.service}}/values-prod.yaml
              - $values/env/prod/global.yaml
        - repoURL: https://github.com/your-github-org/rems-microconfig.git        # PLACEHOLDER org
          targetRevision: main
          ref: values
```

🟡 Replace `your-github-org/REMS-AWS-Architecture` with the real platform repository (`<owner>/<repo>`) in `cicd/argocd/**` and `terraform/cicd/**/terraform.tfvars` / `envs/*.tfvars`.

## Steps

1. Deploy a new version: merge to `main` in the service repo. CI bumps `apps/<svc>/values-dev.yaml` and auto-merges, then ArgoCD dev syncs.
2. Promote:

   ```bash
   gh workflow run promote.yml -R <org>/rems-microconfig -f service=rems-api -f path=dev-to-staging
   gh workflow run promote.yml -R <org>/rems-microconfig -f service=rems-api -f path=staging-to-prod
   ```

3. Watch:

   ```bash
   argocd app get rems-prod-rems-api
   kubectl argo rollouts get rollout rems-api -n rems --watch
   ```

Manual render to debug (never `helm install` into a GitOps-managed namespace):

```bash
helm dependency build helm/charts/rems-api
helm template rems-api helm/charts/rems-api -n rems \
  -f helm/charts/rems-api/values-prod.yaml -f helm/environments/prod/global.yaml
```

## Verification

```bash
argocd app list -l rems.io/layer=application
kubectl get rollouts -n rems -n rems-ai
./scripts/smoke-test.sh https://<host> rems-prod
```

Expected: all applications `Synced` / `Healthy`, rollouts `Healthy`, smoke test `ok` lines only.

## Security considerations

* AppProject `rems` can deploy only to `rems` and `rems-ai`, can't create cluster-scoped resources, and can't change ResourceQuota/LimitRange.
* Prod sync windows (Terraform-managed variant): allow from 04:30 UTC for 8 h on Mon–Thu, deny from 12:30 UTC for 16 h (`syncWindows` in `terraform/cicd/argocd/apps.tf`). `manualSync = true` lets on-call override in an incident.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Unable to resolve '$values/apps/...'` | The values file doesn't exist in microconfig for that env (prod-dr ignores missing files by design) |
| `ComparisonError: missingkey` | The list-generator element is missing a key (`goTemplateOptions: missingkey=error`) |
| App `Progressing` forever | Rollout paused at a step, or analysis is running. Check with `kubectl argo rollouts get rollout` |

## Rollback

See [rollback procedure](../06-cicd/rollback-procedure.md). In short: `rollback.yml` in microconfig, or `argocd app rollback rems-prod-<svc> <history-id>` (this disables auto-sync until it's re-enabled).
