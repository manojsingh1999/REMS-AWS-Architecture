variable "github_org" {
  description = "GitHub organisation that owns the REMS repositories (PLACEHOLDER)."
  type        = string
}

variable "config_repo_name" {
  description = "Name of the common microconfig (GitOps) repository."
  type        = string
  default     = "rems-microconfig"
}

variable "platform_repo_name" {
  description = "This repository (Helm charts, Terraform, ArgoCD bootstrap)."
  type        = string
  default     = "REMS-AWS-Architecture"
}

variable "environments" {
  description = "Environments that get a values file per service in the microconfig repo."
  type        = list(string)
  default     = ["dev", "staging", "prod", "prod-dr"]
}

variable "service_repos" {
  description = "Service name (= ECR repo = Helm chart) -> GitHub repository name of its source code."
  type        = map(string)
  default = {
    "rems-frontend"         = "rems-frontend"
    "rems-api"              = "rems-api"
    "authorization-service" = "authorization-service"
    "data-governance"       = "data-governance"
    "metadata-rca"          = "metadata-rca"
    "chat-engine"           = "chat-engine"
    "mcp-server"            = "mcp-server"
  }
}

variable "manage_service_repo_settings" {
  description = "Write CI variables/secrets into the service repos (false if those repos do not exist yet)."
  type        = bool
  default     = true
}

variable "platform_team" {
  description = "GitHub team slug that owns prod/staging config (CODEOWNERS)."
  type        = string
  default     = "rems-platform"
}

variable "sre_team" {
  description = "GitHub team slug that co-approves prod changes (CODEOWNERS)."
  type        = string
  default     = "rems-sre"
}

variable "ecr_registry" {
  description = "ECR registry host in the Shared Services account (terraform/global/shared-services)."
  type        = string
}

variable "ecr_push_role_arn" {
  description = "GitHub OIDC role that may push to ECR (output ecr_push_role_arn of shared-services)."
  type        = string
}

variable "config_app_id" {
  description = "ID of the GitHub App that opens/auto-merges PRs in the microconfig repo (created once in the org UI)."
  type        = string
}

variable "config_app_private_key" {
  description = "Private key (PEM) of that GitHub App. Pass via TF_VAR_config_app_private_key; never commit it."
  type        = string
  sensitive   = true
}

variable "require_signed_commits" {
  description = "Require verified signatures on main. Enable once the CI bot commits through the GitHub API (API commits are signed by GitHub)."
  type        = bool
  default     = false
}
