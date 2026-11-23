variable "account_id" {
  description = "Target account ID."
  type        = string
}

variable "environment" {
  description = "dev | staging | prod | shared"
  type        = string
}

variable "region" {
  description = "Home region."
  type        = string
  default     = "ap-south-1"
}

variable "dr_region" {
  description = "DR region for the replicated state bucket."
  type        = string
  default     = "ap-southeast-1"
}

variable "replicate_state" {
  description = "Replicate the state bucket to the DR region (prod)."
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub organisation (PLACEHOLDER)."
  type        = string
}

variable "platform_repo" {
  description = "This repository's name."
  type        = string
  default     = "REMS-AWS-Architecture"
}

variable "admin_role_arns" {
  description = "Key administrators."
  type        = list(string)
  default     = []
}
