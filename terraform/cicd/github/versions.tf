# GitHub side of the GitOps flow (run once, org level):
#   * the common "microconfig" repository (image tags + per-env values for every REMS service)
#   * branch protection: PRs + required "validate" check; prod/staging files need CODEOWNER approval
#   * seed layout copied from this platform repo (helm/charts/*/values-<env>.yaml, helm/environments/*/global.yaml)
#   * CI variables/secrets in every service repo (ECR push role, registry, config-repo GitHub App)
#
# Auth: export GITHUB_TOKEN (org admin, or a GitHub App installation token) before terraform plan/apply.

terraform {
  required_version = ">= 1.10"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.4"
    }
  }

  backend "s3" {}
}

provider "github" {
  owner = var.github_org
}
