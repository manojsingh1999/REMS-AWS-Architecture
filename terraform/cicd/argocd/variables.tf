variable "account_id" {
  description = "AWS account of the cluster (guard against the wrong account)."
  type        = string
}

variable "region" {
  description = "Cluster region."
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "dev | staging | prod | prod-dr (selects values-<environment>.yaml in the microconfig repo)."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod", "prod-dr"], var.environment)
    error_message = "environment must be dev, staging, prod or prod-dr."
  }
}

variable "cluster_name" {
  description = "EKS cluster name (terraform output cluster_name)."
  type        = string
}

variable "github_org" {
  description = "GitHub organisation (PLACEHOLDER)."
  type        = string
}

variable "platform_repo" {
  description = "Repository holding Helm charts and ArgoCD add-on definitions."
  type        = string
  default     = "REMS-AWS-Architecture"
}

variable "config_repo" {
  description = "Common microconfig (GitOps values) repository."
  type        = string
  default     = "rems-microconfig"
}

variable "target_revision" {
  description = "Git branch/tag ArgoCD tracks in both repositories."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo/argo-cd chart version."
  type        = string
  default     = "7.7.10"
}

variable "argocd_apps_chart_version" {
  description = "argo/argocd-apps chart version (projects, applications, applicationsets)."
  type        = string
  default     = "2.0.2"
}

variable "argocd_hostname" {
  description = "Internal hostname of the ArgoCD UI (internal ALB)."
  type        = string
}

variable "auto_sync" {
  description = "Automated sync for REMS services (true everywhere; prod is gated by PR approvals + sync windows)."
  type        = bool
  default     = true
}

variable "services" {
  description = "REMS services: name -> { namespace, wave }."
  type = map(object({
    namespace = string
    wave      = number
  }))
  default = {
    "authorization-service" = { namespace = "rems", wave = 1 }
    "rems-api"              = { namespace = "rems", wave = 2 }
    "data-governance"       = { namespace = "rems", wave = 2 }
    "metadata-rca"          = { namespace = "rems-ai", wave = 2 }
    "mcp-server"            = { namespace = "rems-ai", wave = 3 }
    "chat-engine"           = { namespace = "rems-ai", wave = 3 }
    "rems-frontend"         = { namespace = "rems", wave = 4 }
  }
}
