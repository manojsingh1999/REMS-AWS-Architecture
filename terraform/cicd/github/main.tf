locals {
  template_dir = "${path.module}/../../../cicd/microconfig-repo-template"
  charts_dir   = "${path.module}/../../../helm/charts"
  envs_dir     = "${path.module}/../../../helm/environments"

  # apps/<service>/values-<env>.yaml seeded from the platform repo's current values
  seed_values = {
    for pair in setproduct(keys(var.service_repos), var.environments) :
    "apps/${pair[0]}/values-${pair[1]}.yaml" => "${local.charts_dir}/${pair[0]}/values-${pair[1]}.yaml"
  }

  seed_globals = {
    for env in var.environments : "env/${env}/global.yaml" => "${local.envs_dir}/${env}/global.yaml"
  }

  # Files Terraform keeps in sync (repo policy) vs. seed files that CI owns afterwards.
  managed_files = {
    "README.md"                      = file("${local.template_dir}/README.md")
    ".github/workflows/validate.yml" = file("${local.template_dir}/.github/workflows/validate.yml")
    ".github/workflows/promote.yml"  = file("${local.template_dir}/.github/workflows/promote.yml")
    ".github/workflows/rollback.yml" = file("${local.template_dir}/.github/workflows/rollback.yml")
    ".github/CODEOWNERS" = templatefile("${local.template_dir}/CODEOWNERS.tftpl", {
      org           = var.github_org
      platform_team = var.platform_team
      sre_team      = var.sre_team
    })
  }
}

# ------------------------------------------------------------------ the common microconfig repository
resource "github_repository" "config" {
  name        = var.config_repo_name
  description = "REMS GitOps configuration: image tags and per-environment values for every service. Synced to EKS by ArgoCD."
  visibility  = "private"

  has_issues             = true
  has_wiki               = false
  has_projects           = false
  auto_init              = true
  allow_merge_commit     = false
  allow_rebase_merge     = false
  allow_squash_merge     = true
  allow_auto_merge       = true # CI bot enables auto-merge; dev PRs merge once "validate" passes
  delete_branch_on_merge = true
  vulnerability_alerts   = true
  archive_on_destroy     = true # never lose deployment history
}

resource "github_repository_file" "managed" {
  for_each            = local.managed_files
  repository          = github_repository.config.name
  branch              = "main"
  file                = each.key
  content             = each.value
  commit_message      = "chore(terraform): manage ${each.key}"
  commit_author       = "rems-terraform"
  commit_email        = "rems-terraform@users.noreply.github.com"
  overwrite_on_create = true
}

# Seed files: created once from the platform repo, then owned by CI (tag bumps) and promotion PRs.
resource "github_repository_file" "seed" {
  for_each            = merge(local.seed_values, local.seed_globals)
  repository          = github_repository.config.name
  branch              = "main"
  file                = each.key
  content             = file(each.value)
  commit_message      = "chore(terraform): seed ${each.key}"
  commit_author       = "rems-terraform"
  commit_email        = "rems-terraform@users.noreply.github.com"
  overwrite_on_create = true

  lifecycle {
    ignore_changes = [content, commit_message]
  }
}

# ------------------------------------------------------------------ protection of main
# Every change is a PR. "validate" (yamllint + schema + tag format) must pass.
# CODEOWNERS only covers staging/prod files, so the bot's dev PRs auto-merge on green checks,
# while staging/prod promotions need platform (and SRE for prod) approval.
resource "github_branch_protection" "main" {
  #checkov:skip=CKV_GIT_5:Two-person rule is path-scoped - "validate" fails prod/prod-dr PRs with fewer than 2 approvals; dev bot PRs need none
  #checkov:skip=CKV_GIT_6:Controlled by var.require_signed_commits; enable once the bot commits through the GitHub API (verified)
  repository_id = github_repository.config.node_id
  pattern       = "main"

  enforce_admins                  = true
  require_signed_commits          = var.require_signed_commits
  required_linear_history         = true
  require_conversation_resolution = true
  allows_deletions                = false
  allows_force_pushes             = false

  required_status_checks {
    strict   = true
    contexts = ["validate"]
  }

  required_pull_request_reviews {
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = true
    required_approving_review_count = 0 # approvals come from CODEOWNERS rules (prod/staging only)
  }

  # Seed and policy files must exist before direct commits are blocked.
  depends_on = [github_repository_file.managed, github_repository_file.seed]
}
