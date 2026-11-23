# rems-microconfig: GitOps configuration for REMS

This repository is the **single source of truth for what runs in every REMS environment**. ArgoCD in each EKS cluster
watches it. Helm charts live in the platform repo (`REMS-AWS-Architecture/helm/charts`), and only *values* live here.

```
apps/<service>/values-dev.yaml       image.tag / image.digest + dev overrides       (written by the CI bot)
apps/<service>/values-staging.yaml   promoted by PR                                 (CODEOWNERS: platform)
apps/<service>/values-prod.yaml      promoted by PR, change window                  (CODEOWNERS: platform + SRE)
apps/<service>/values-prod-dr.yaml   DR warm-standby overrides
env/<env>/global.yaml                region, VPC CIDR, ACM/WAF ARNs, ALB log bucket (from Terraform outputs)
```

## Flow

1. A service repo merges to `main`, then CI creates a date tag `YYYY.MM.DD-<run>`, lints, builds, scans with Trivy, pushes to ECR and signs.
2. The CI bot (GitHub App) opens a PR here that bumps `apps/<svc>/values-dev.yaml` and enables auto-merge.
3. `validate` passes and the PR merges. ArgoCD (dev) syncs, and Argo Rollouts runs the canary with automatic analysis.
4. Promotion: run `promote.yml` (`dev → staging`, `staging → prod`). It copies the **same** tag and digest, with no rebuild, and needs CODEOWNER approval.
5. Rollback: run `rollback.yml`, or revert the PR. ArgoCD syncs the previous tag.

Direct pushes to `main` are blocked for everyone (branch protection with admins included). Managed by `terraform/cicd/github`.
