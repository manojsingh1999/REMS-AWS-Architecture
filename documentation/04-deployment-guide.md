# Deployment Guide (every command, in order)

> **Nothing in this repository has been applied to any AWS account.** Every step below creates billable resources
> and must be run by an authorised operator after reviewing the plan. Replace all `PLACEHOLDER` values first:
> `grep -rn PLACEHOLDER --include=*.tf --include=*.tfvars --include=*.hcl --include=*.yaml .`

## 0. Prerequisites

| Tool | Version |
|---|---|
| Terraform | ≥ 1.10 |
| AWS CLI | v2, with IAM Identity Center profiles per account |
| kubectl / kustomize | 1.31 / 5.5 |
| Helm | 3.16 |
| argocd CLI, jq, yq, psql 16 | latest |
| Optional, for validation | kubeconform, actionlint, opa, promtool, k6, checkov, tflint, shellcheck |

```bash
./scripts/validate.sh            # offline validation of everything (no AWS access needed)
```

## 1. Landing zone (management account, platform admins)

```bash
cd terraform/landing-zone
terraform init -backend-config=backend.hcl
# Phase 1: organization, OUs and accounts (providers for member accounts need the account IDs first)
terraform apply -target=aws_organizations_organization.this \
                -target=aws_organizations_organizational_unit.top \
                -target=aws_organizations_organizational_unit.workloads \
                -target=aws_organizations_account.this
# Phase 2: SCPs, delegated admins, org CloudTrail, Log Archive bucket, security baseline
terraform plan -out=tfplan && terraform apply tfplan
terraform output account_ids        # copy into the tfvars of the stacks below
```

## 2. Per-account bootstrap (state bucket, permission boundaries, GitHub OIDC roles)

```bash
cd terraform/global/bootstrap
for env in dev staging prod; do
  AWS_PROFILE=rems-${env}-admin terraform init -reconfigure      # local state for the bootstrap
  AWS_PROFILE=rems-${env}-admin terraform apply -var-file=${env}.tfvars -state=${env}.tfstate
done
# Outputs: state_bucket, github_role_arns, workload_permissions_boundary_arn
#  -> set GitHub Environment variables AWS_ROLE_PLAN / AWS_ROLE_APPLY per environment
#  -> set permissions_boundary_arn in terraform/environments/<env>/terraform.tfvars
```

## 3. Shared services (ECR + image push role)

```bash
cd terraform/global/shared-services
AWS_PROFILE=rems-shared-admin terraform init -backend-config=backend.hcl
AWS_PROFILE=rems-shared-admin terraform apply
terraform output ecr_push_role_arn   # -> GitHub org variable AWS_ECR_PUSH_ROLE; ECR_REGISTRY = <acct>.dkr.ecr.ap-south-1.amazonaws.com
```

## 3b. GitHub: common microconfig repo + service repo CI settings

```bash
# Create the GitHub App "rems-config-bot" once in the org UI (Contents RW + Pull requests RW, installed on rems-microconfig only)
cd terraform/cicd/github
export GITHUB_TOKEN=<org-admin token>  TF_VAR_config_app_private_key="$(cat rems-config-bot.pem)"
terraform init -backend-config=backend.hcl
terraform apply     # repo, branch protection, CODEOWNERS, validate/promote/rollback workflows, seed values, CI vars/secrets
```

## 4. Environments (via the `terraform` GitHub workflow, or locally for the first run)

```bash
cd terraform/environments/dev
AWS_PROFILE=rems-dev-admin terraform init -backend-config=backend.hcl
AWS_PROFILE=rems-dev-admin terraform plan -out=tfplan
AWS_PROFILE=rems-dev-admin terraform apply tfplan
# repeat for staging and prod; then prod-dr (reads prod outputs through remote state):
cd ../prod-dr && AWS_PROFILE=rems-prod-admin terraform init -backend-config=backend.hcl && terraform apply
```

Copy the outputs into the GitOps values. These are the only manual value transfers:

| Terraform output | Goes to |
|---|---|
| `edge.waf_acl_arn`, `edge.certificate_arn`, `buckets.alb_logs` | `helm/environments/<env>/global.yaml` |
| `vpc_id`, `cluster_name`, `karpenter.interruption_queue` | `kubernetes/platform-addons/*/values-<env>.yaml` |
| `alerts_topic_arn`, region | `monitoring/kube-prometheus-stack/values.yaml` (Alertmanager SNS) |
| `buckets.telemetry` | `monitoring/loki`, `monitoring/tempo` values |
| `aurora.core_proxy_endpoint`, `ai.guardrail_id`, `ai.guardrail_version` | `ai-infrastructure/llm-gateway/values.yaml` |

## 5. Secrets that never go through Terraform state

```bash
aws secretsmanager put-secret-value --secret-id rems/prod/llm/openai     --secret-string "$OPENAI_KEY"
aws secretsmanager put-secret-value --secret-id rems/prod/llm/anthropic  --secret-string "$ANTHROPIC_KEY"
aws secretsmanager put-secret-value --secret-id rems/prod/llm/master-key --secret-string "$(openssl rand -hex 32)"
```

## 6. Database bootstrap (from a host inside the VPC, e.g. SSM session)

```bash
AWS_REGION=ap-south-1 ./database/scripts/bootstrap-roles.sh prod core
AWS_REGION=ap-south-1 ./database/scripts/bootstrap-roles.sh prod rag
```

## 7. Cluster GitOps bootstrap

Preferred (Terraform-managed ArgoCD, read-only deploy keys, services synced from rems-microconfig):

```bash
cd terraform/cicd/argocd
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file=envs/dev.tfvars      # ArgoCD (HA) + AppProjects + platform root app + rems-services ApplicationSet
```

Alternative without Terraform (same result, manual repo credentials):

```bash
./scripts/bootstrap-cluster.sh dev       # installs ArgoCD (HA), AppProjects, root app-of-apps
# ArgoCD then syncs, in waves:
#   -40 cluster-base (namespaces, quotas, netpols, Karpenter pools, ClusterSecretStore, LLM gateway secrets)
#   -30 Karpenter | -20 ALB controller, ESO, metrics-server, KEDA, Rollouts, Kyverno | -10 external-dns, kube-prometheus-stack
#    -5 VictoriaMetrics, Loki, Tempo, OTel | -1 policies, analysis templates, rules, dashboards | 0 LLM gateway
#     1..4 REMS services (authz -> api/governance/rca -> mcp/chat -> frontend)
argocd app list
```

## 8. Application delivery

```bash
# service repos call the reusable workflow -> date tag, image pushed + signed, auto-merged PR to rems-microconfig (dev)
gh workflow run promote.yml -R your-github-org/rems-microconfig -f service=rems-api -f path=dev-to-staging
gh workflow run load-test.yml -f scenario=normal-load
gh workflow run promote.yml -R your-github-org/rems-microconfig -f service=rems-api -f path=staging-to-prod   # 2 approvals
kubectl argo rollouts get rollout rems-api -n rems --watch                            # canary progress
```

## 9. Verification

```bash
./scripts/smoke-test.sh https://app.rems.example.com rems-prod
kubectl get nodeclaims; kubectl get scaledobjects,hpa -A; kubectl get externalsecrets -A
```

## 10. Day-2

| Task | Command / file |
|---|---|
| Rollback | `gh workflow run rollback.yml -R your-github-org/rems-microconfig -f service=<svc> -f environment=prod -f reason=<INC>` |
| AZ drill (staging) | `load-testing/chaos/run-chaos.sh az ap-south-1b` |
| DR failover | `runbooks/dr-regional-failover.md` |
| Rotate DB password | `database/scripts/rotate-service-password.sh prod core rems-api` |
| Cost model refresh | `python3 scripts/cost_model.py` |
| Destroy dev (deletion protection off in dev) | `terraform -chdir=terraform/environments/dev destroy` |
