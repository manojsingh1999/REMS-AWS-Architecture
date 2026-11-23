# terraform/cicd: GitOps delivery as code

| Stack | Scope | Creates |
|---|---|---|
| `github/` | once, org level | `rems-microconfig` repo, branch protection (PR + `validate` check, CODEOWNERS for staging/prod), managed workflows (`validate`, `promote`, `rollback`), seed values (`apps/<svc>/values-<env>.yaml`, `env/<env>/global.yaml`), CI variables/secrets in the 7 service repos |
| `argocd/` | once per cluster (`envs/<env>.tfvars`) | `argocd` namespace, read-only ED25519 deploy keys for the platform and microconfig repos, ArgoCD (HA, Helm), AppProjects, platform root Application, `rems-services-<env>` ApplicationSet (charts from the platform repo, values from rems-microconfig) |

End-to-end flow: service repo merge → date tag `YYYY.MM.DD-<run>` → lint → build → Trivy gate → push to ECR + cosign → PR to rems-microconfig (auto-merge for dev) → ArgoCD sync → Argo Rollouts canary → promote/rollback through PRs in rems-microconfig.

Providers: `integrations/github ~> 6.4` (auth via `GITHUB_TOKEN`), `hashicorp/helm ~> 2.16`, `hashicorp/kubernetes ~> 2.33` (EKS token through `aws eks get-token`), `hashicorp/tls ~> 4.0`.
Deploy-key private keys are stored in Terraform state (S3, KMS-encrypted, access restricted) and in the ArgoCD repository Secret (KMS envelope encryption).
