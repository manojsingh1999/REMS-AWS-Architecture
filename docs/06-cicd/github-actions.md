# GitHub Actions

**Status:** ✅ 5 workflows in `.github/workflows/` + 3 microconfig workflows in `cicd/microconfig-repo-template/.github/workflows/`, all `actionlint`-clean. `terraform/cicd/github` manages the microconfig repo and the service repo CI settings. ⚠️ None of the workflows have run on GitHub yet, because the repository variables, environments and GitHub App aren't created.

## Workflows

| File | Trigger | Purpose |
|---|---|---|
| `.github/workflows/app-build.yml` | `workflow_call` (from each service repo) | Test → SonarQube → Trivy fs (PR). Date tag → hadolint → build → Trivy image gate → push to ECR → SBOM + cosign → release → PR to microconfig (merge) |
| `.github/workflows/terraform.yml` | PR / push to main on `terraform/**`, `security/iam/**` | fmt, validate, tf_static_check, tflint, Checkov, plan per env, apply with approvals |
| `.github/workflows/k8s-validate.yml` | PR on charts / manifests | helm lint + template + kubeconform, Kyverno CLI against rendered charts, kustomize builds, OPA tests, yamllint, Checkov |
| `.github/workflows/security-scan.yml` | nightly `30 21 * * *` (03:00 IST) | Gitleaks, Trivy config scan, re-scan of running prod images for new CVEs |
| `.github/workflows/load-test.yml` | manual + weekly `0 22 * * 0` | k6 scenarios against staging |
| microconfig `validate.yml` | PR in rems-microconfig | Schema/approval checks (required status check `validate`) |
| microconfig `promote.yml` | manual: `service`, `path` (`dev-to-staging` / `staging-to-prod`) | Copies the same tag + digest to the next env through a PR |
| microconfig `rollback.yml` | manual: `service`, `environment`, `reason` | Reverts to the previous tag through a PR |

## Using the reusable build workflow in a service repo

```yaml
# <service-repo>/.github/workflows/ci.yml
name: ci
on:
  pull_request:
  push:
    branches: [main]
jobs:
  ci:
    uses: <org>/<platform-repo>/.github/workflows/app-build.yml@main
    with:
      service: rems-api
      test-command: "<repository-specific test command>"
    secrets: inherit
```

The header of `app-build.yml` shows a pytest-based example. Use the real test command of each repository.

## Configuration (variables and secrets)

| Name | Kind | Where | Set by |
|---|---|---|---|
| `ECR_REGISTRY` | variable | service repos | `terraform/cicd/github` (`github_actions_variable.service`) |
| `AWS_ECR_PUSH_ROLE` | variable | service repos | same (value: `terraform/global/shared-services` output `ecr_push_role_arn`) |
| `CONFIG_REPO`, `CONFIG_APP_ID`, `SERVICE_NAME` | variables | service repos | same |
| `CONFIG_APP_PRIVATE_KEY` | secret | service repos | same, from `TF_VAR_config_app_private_key` (never in tfvars) |
| `SONAR_TOKEN` / `SONAR_HOST_URL` | secret / variable | service repos | 📋 manual |
| `AWS_ROLE_PLAN` / `AWS_ROLE_APPLY` | environment variables | this repo | 📋 manual, from bootstrap output `github_role_arns` |

## Steps: create the microconfig repo and CI settings

1. 📋 Create a GitHub App `rems-config-bot` in the org UI with Contents RW + Pull requests RW, installed **only** on `rems-microconfig`. Download its private key and keep it out of Git.
2. Apply:

   ```bash
   cd terraform/cicd/github
   $EDITOR terraform.tfvars          # github_org, ecr_registry, ecr_push_role_arn, config_app_id, service_repos
   export GITHUB_TOKEN="<org-admin fine-grained token>"           # never commit
   export TF_VAR_config_app_private_key="$(cat /secure/path/rems-config-bot.pem)"
   terraform init -backend-config=backend.hcl
   terraform plan -out=tfplan && terraform apply tfplan
   unset GITHUB_TOKEN TF_VAR_config_app_private_key
   ```

3. Set this repository's environment variables for the Terraform workflow (see [Terraform deployment](../03-terraform/terraform-deployment.md)).

## Verification

```bash
gh variable list -R <org>/<service-repo>
gh secret list -R <org>/<service-repo>
gh api repos/<org>/rems-microconfig/branches/main/protection --jq '.required_status_checks.contexts'
actionlint .github/workflows/*.yml cicd/microconfig-repo-template/.github/workflows/*.yml
```

## Security considerations

* All AWS access is OIDC. `permissions: contents: read` by default. Only the build job gets `id-token: write` and `contents: write`.
* 🟡 **Repository name check:** `platform_repo` defaults to `REMS-AWS-Architecture` (`terraform/global/bootstrap/variables.tf`, `terraform/cicd/argocd/variables.tf`). Set it to this repository's exact name (`platform_repo = "<repo-name>"`), or the OIDC trust (`sub` claim) and ArgoCD repo URLs won't match.
* Third-party actions are pinned to major versions. Pinning to commit SHAs is recommended (Dependabot config in `.github/dependabot.yml` keeps them updated).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not assume role with OIDC` | Repo/org name mismatch or a missing environment (see above) |
| `Resource not accessible by integration` when opening the microconfig PR | The GitHub App isn't installed on rems-microconfig, or the permissions are missing |
| Auto-merge not available | Enable "Allow auto-merge" on the repo (`github_repository.config` sets it) |

## Rollback

Workflows are versioned in Git. Revert the workflow change. Service repos call `@main`. For stability, pin to a tag (`@v1`) once the pipeline is proven.
