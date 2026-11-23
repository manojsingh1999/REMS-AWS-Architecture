# Implementation Status

Snapshot date: **2026-11-23**.

**Summary:** the infrastructure code for every area of the problem statement is in the repository and passes offline validation. **No AWS resource has been created and nothing has been deployed.** Remaining work is about (a) real account and application data replacing placeholders, (b) a few gaps found while writing this guide (listed under *Pending*), and (c) validation that can only happen against real AWS and real services.

## ✅ Completed (code present, validated offline)

| Area | Repository paths | Validation |
|---|---|---|
| Landing zone: Organizations, OUs, 7 accounts, 7 SCPs, tag policy, org CloudTrail, delegated security services | `terraform/landing-zone/`, `security/iam/scp/` | tf_static_check, Checkov, JSON parse |
| Account bootstrap: state bucket + DR replica, GitHub OIDC roles, permission boundaries | `terraform/global/bootstrap/`, `terraform/modules/github-oidc/`, `security/iam/permission-boundary-*.json` | tf_static_check, Checkov |
| Shared ECR with replication, scanning, immutable tags, push role | `terraform/global/shared-services/`, `terraform/modules/ecr/` | tf_static_check, Checkov |
| Environment composition (VPC, EKS, Karpenter, Pod Identity, Aurora ×2 + Proxy + Global DB, Valkey, S3, KMS, WAF, ACM, Cognito, Bedrock guardrail, monitoring, backup, FIS role) | `terraform/modules/*`, `terraform/environments/{dev,staging,prod,prod-dr}/` | tf_static_check (26 dirs), Checkov 1 428/0 |
| GitHub microconfig repo, branch protection, CODEOWNERS, workflows, service repo CI vars | `terraform/cicd/github/`, `cicd/microconfig-repo-template/` | tf_static_check, actionlint |
| ArgoCD HA, deploy keys, AppProjects, root app, rems-services ApplicationSet | `terraform/cicd/argocd/`, `cicd/argocd/` | tf_static_check, kubeconform |
| Kubernetes base (namespaces + PSA, quotas, NetworkPolicies, RBAC, PriorityClasses, Karpenter pools, ClusterSecretStore, overprovisioning) and 4 overlays | `kubernetes/base/`, `kubernetes/overlays/` | kustomize + kubeconform (172 objects), yamllint |
| Platform add-on values | `kubernetes/platform-addons/` | yamllint |
| Helm library chart + 7 service charts (Rollout canary, HPA/KEDA, PDB, NetworkPolicy, Ingress, ExternalSecret, ServiceMonitor) | `helm/charts/`, `helm/environments/` | 28 renders + kubeconform, Checkov 771/0 |
| CI workflows (build, terraform, k8s validate, security scan, load test) | `.github/workflows/` | actionlint |
| Canary analysis templates | `cicd/argo-rollouts/analysis-templates.yaml` | kubeconform |
| Kyverno policies, OPA tenant + MCP policies with tests | `security/kyverno/`, `security/opa/` | kubeconform, `opa test` 12/12 |
| Observability stack values, 114 rules, 3 dashboards, SLOs | `monitoring/` | promtool, kubeconform |
| SQL (roles, grants, RLS, pgvector) and DB scripts | `database/` | pglast parser, shellcheck |
| LLM gateway values + k8s component, RAG and MCP design | `ai-infrastructure/` | kubeconform, yamllint |
| k6 scenarios (7), k6-operator, FIS templates, chaos driver | `load-testing/` | `k6 inspect`, JSON parse, shellcheck |
| Scripts (validate, bootstrap, smoke test, cost model, offline checkers) | `scripts/` | shellcheck, executed locally |
| Runbooks (12), design docs (10, 19 diagrams), documentation set | `runbooks/`, `architecture/`, `documentation/` | Mermaid parser |
| Implementation guide (85 files: 82 topic pages, index, status, changelog) + root README | `docs/`, `README.md` | link check, Mermaid parser, secret scan |

## 🔄 In progress

| Item | Notes |
|---|---|
| Replacing placeholders with real account, domain and application values | Prerequisite for the first `terraform apply` (see *Blocked*) |

## 📋 Pending (gaps and follow-ups found while documenting)

| # | Item | Where | Impact |
|---|---|---|---|
| 1 | Environment roots don't re-export the module outputs `vpc_id` and `alerts_topic_arn` | `terraform/environments/*/outputs.tf` | Manual lookup needed (workaround in [infrastructure deployment](02-aws-infrastructure/infrastructure-deployment.md)) |
| 2 | `platform_repo` default (`REMS-AWS-Architecture`) must match this repository's real name. ArgoCD repo URLs use `your-github-org` | `terraform/global/bootstrap/variables.tf`, `terraform/cicd/argocd/variables.tf`, `cicd/argocd/**` | OIDC trust and ArgoCD repo access fail until set |
| 3 | Route 53 health checks and failover records for DR | `terraform/modules/rems-environment/edge.tf` (absent) | DR traffic shift is manual |
| 4 | Grafana admin and OIDC client secrets: ExternalSecrets and Secrets Manager entries missing | `monitoring/kube-prometheus-stack/values.yaml` | Grafana login not functional |
| 5 | `security/secrets-rotation.md` mentions `--master`, but `rotate-service-password.sh` doesn't implement it | `database/scripts/rotate-service-password.sh` | Master rotation is manual |
| 6 | `interface_endpoints` isn't exposed per environment | `terraform/modules/rems-environment/network.tf` | Dev cost optimisation needs a module edit |
| 7 | Network account resources (Transit Gateway, Network Firewall FQDN egress) | Network account (no stack) | External LLM egress not FQDN-filtered |
| 8 | IAM Identity Center permission sets | manual | Role ARNs in tfvars are placeholders |
| 9 | FIS stop conditions for Aurora and pod chaos are `none` | `load-testing/chaos/fis-aurora-failover.json`, `fis-eks-pod-chaos.json` | Add before prod game days |
| 10 | Management-account bootstrap (`mgmt.tfvars`) and a backend block for migrating bootstrap state | `terraform/global/bootstrap/` | Landing-zone backend bucket must be created first |
| 11 | `.terraform.lock.hcl` files | all stacks | Commit after the first online `terraform init` |
| 12 | GitHub environments, variables, GitHub App, SonarQube | GitHub settings | Workflows can't run until configured |
| 13 | `dr-scale-up` PR prepared in rems-microconfig | microconfig repo | Runbook step 4 |
| 14 | LiteLLM image tag pinned, Bedrock model IDs re-checked for the regions | `ai-infrastructure/llm-gateway/values.yaml` | Gateway can't start with a placeholder tag |
| 15 | Silo tenancy option, service mesh / mTLS, CIS benchmark run, Infracost, RAG recall dataset | design only | Optional hardening |
| 16 | Branch protection on the platform and service repos, and CODEOWNERS handles (`your-github-org` placeholders) | GitHub settings, `.github/CODEOWNERS` | `main` is unprotected until applied ([branching strategy](06-cicd/git-branching-strategy.md)) |

## ⛔ Blocked

| Item | Blocked on |
|---|---|
| Any `terraform apply` / deployment | Explicit approval from the repository owner + real account IDs, domains and role ARNs |
| Application-specific values (ports, probes, metrics path, env vars, API routes, worker command) | Service repositories / OpenAPI specs (assumptions P1–P9 in `documentation/02-assumptions.md`) |

## ⚠️ Not yet validated

| Check | Why not | How to validate |
|---|---|---|
| `terraform validate` / `fmt` / `plan` with real providers | Terraform binary and provider downloads unavailable in the build environment | `.github/workflows/terraform.yml` or `./scripts/validate.sh terraform` locally |
| `helm lint` with Helm | Helm binary unavailable (offline renderer used instead) | `./scripts/validate.sh helm` |
| Kyverno CLI against rendered charts | Not runnable in the build sandbox | `k8s-validate.yml` job `kyverno` |
| Gitleaks, Trivy, tflint | Not installed in the build environment | `security-scan.yml`, `terraform.yml` |
| Runtime behaviour (autoscaling, failover, canary analysis, NetworkPolicy enforcement) | Nothing deployed | Staging drills: [failure scenarios](12-testing/failure-scenarios.md) |
| Load test results | Nothing deployed, routes are placeholders | [k6 load testing](12-testing/k6-load-testing.md) |
| RPO/RTO | No DR drill | [recovery runbook](11-ha-dr/recovery-runbook.md) |
| Cost estimate vs real bill | No usage | Cost Explorer after 1–2 months |
