# Deployment Runbook

**Status:** ✅ Procedures documented against the real scripts and workflows. ⚠️ Not yet executed. Follow the first-time order exactly. Every `apply` creates billable resources and needs explicit approval.

## A. First-time platform deployment (per environment)

| # | Step | Command / page | Done when |
|---|---|---|---|
| 0 | Replace placeholders, run offline validation | `grep -rn PLACEHOLDER ...`, `./scripts/validate.sh` | No FAIL lines |
| 1 | Landing zone (once) | [account setup](../02-aws-infrastructure/aws-account-setup.md) | Accounts ACTIVE, SCPs attached |
| 2 | Account bootstrap | [IAM configuration](../02-aws-infrastructure/iam-configuration.md) | State bucket + OIDC roles exist |
| 3 | Shared services (ECR) | [ECR integration](../06-cicd/ecr-integration.md) | Repos + push role exist |
| 4 | GitHub (microconfig + CI vars) | [GitHub Actions](../06-cicd/github-actions.md) | `rems-microconfig` protected, vars set |
| 5 | Environment stack | [infrastructure deployment](../02-aws-infrastructure/infrastructure-deployment.md) | `terraform plan` shows no changes |
| 6 | Copy outputs into GitOps values | same page, "Outputs to copy" | No PLACEHOLDER in env values |
| 7 | Provider secrets + DB bootstrap | [secrets](../07-security/secrets-management.md), [PostgreSQL](../08-database/postgresql-setup.md) | ExternalSecrets sync later, `bootstrap-roles.sh` OK |
| 8 | ArgoCD | [ArgoCD setup](../06-cicd/argocd-setup.md) | Platform apps Synced/Healthy |
| 9 | Services | [application deployment](../05-helm/application-deployment.md) | All rollouts Healthy |
| 10 | Smoke test | `./scripts/smoke-test.sh https://<host> rems-<env>` | Only `ok` lines |
| 11 | Load test (staging) | [k6](../12-testing/k6-load-testing.md) | Pass criteria met |

## B. Routine service release

```bash
# 1. merge to main in the service repo -> CI -> dev auto-deploys
# 2. promote
gh workflow run promote.yml -R <org>/rems-microconfig -f service=<svc> -f path=dev-to-staging
# 3. staging verification (+ load test for risky changes)
gh workflow run load-test.yml -f scenario=normal-load -f base_url=https://<staging-host>
# 4. prod (inside the sync window, 2 approvals)
gh workflow run promote.yml -R <org>/rems-microconfig -f service=<svc> -f path=staging-to-prod
kubectl argo rollouts get rollout <svc> -n <rems|rems-ai> --watch
```

Go / no-go for prod: error budget > 0 for the service (`monitoring/slo/slos.md` policy), no open SEV1/SEV2, staging healthy for ≥ 24 h on the same digest.

## C. Infrastructure change

PR → `terraform.yml` plan comment → review (no unexpected replace/destroy) → merge → dev applies → approve staging → approve prod + prod-dr.

## Rollback

[Rollback procedure](../06-cicd/rollback-procedure.md).
