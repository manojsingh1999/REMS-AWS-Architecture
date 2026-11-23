variable "account_id" {
  description = "Shared Services account ID."
  type        = string
}

variable "region" {
  description = "Home region."
  type        = string
  default     = "ap-south-1"
}

variable "dr_region" {
  description = "ECR replication target."
  type        = string
  default     = "ap-southeast-1"
}

variable "workload_account_ids" {
  description = "Accounts that pull images: { dev = ..., staging = ..., prod = ... }."
  type        = map(string)
}

variable "github_org" {
  description = "GitHub organisation (PLACEHOLDER)."
  type        = string
}

variable "admin_role_arns" {
  description = "KMS administrators."
  type        = list(string)
  default     = []
}
