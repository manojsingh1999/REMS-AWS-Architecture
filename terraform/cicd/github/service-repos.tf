# CI settings in every REMS service repository, consumed by the reusable workflow
# .github/workflows/app-build.yml (OIDC to AWS - no AWS keys are stored anywhere).

locals {
  service_vars = var.manage_service_repo_settings ? merge([
    for svc, repo in var.service_repos : {
      "${svc}|AWS_ECR_PUSH_ROLE" = { repo = repo, name = "AWS_ECR_PUSH_ROLE", value = var.ecr_push_role_arn }
      "${svc}|ECR_REGISTRY"      = { repo = repo, name = "ECR_REGISTRY", value = var.ecr_registry }
      "${svc}|CONFIG_REPO"       = { repo = repo, name = "CONFIG_REPO", value = "${var.github_org}/${var.config_repo_name}" }
      "${svc}|CONFIG_APP_ID"     = { repo = repo, name = "CONFIG_APP_ID", value = var.config_app_id }
      "${svc}|SERVICE_NAME"      = { repo = repo, name = "SERVICE_NAME", value = svc }
    }
  ]...) : {}
}

resource "github_actions_variable" "service" {
  for_each      = local.service_vars
  repository    = each.value.repo
  variable_name = each.value.name
  value         = each.value.value
}

# The GitHub App key lets CI open a PR in the microconfig repo and enable auto-merge.
# Scope of the App installation: contents + pull requests on the microconfig repo only.
resource "github_actions_secret" "config_app_key" {
  for_each        = var.manage_service_repo_settings ? var.service_repos : {}
  repository      = each.value
  secret_name     = "CONFIG_APP_PRIVATE_KEY"
  plaintext_value = var.config_app_private_key
}
