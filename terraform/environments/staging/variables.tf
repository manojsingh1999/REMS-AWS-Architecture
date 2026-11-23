variable "account_id" {
  description = "Staging workload account ID (guards against applying to the wrong account)."
  type        = string
}

variable "region" {
  description = "Primary region."
  type        = string
  default     = "ap-south-1"
}

variable "azs" {
  description = "Three AZs in the primary region."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "domain_name" {
  description = "Public domain for REMS."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID."
  type        = string
  default     = null
}

variable "cognito_domain_prefix" {
  description = "Cognito hosted UI prefix."
  type        = string
}

variable "alert_emails" {
  description = "On-call distribution lists."
  type        = list(string)
  default     = []
}

variable "platform_admin_role_arn" {
  description = "IAM Identity Center PlatformAdmin role ARN (EKS admin, KMS admin)."
  type        = string
}

variable "readonly_role_arn" {
  description = "IAM Identity Center ReadOnly role ARN (EKS view)."
  type        = string
}

variable "oncall_role_arn" {
  description = "IAM Identity Center OnCall role ARN (mapped to the rems-oncall Kubernetes group)."
  type        = string
}

variable "cicd_deploy_role_arn" {
  description = "GitHub OIDC role used by pipelines for read-only cluster checks."
  type        = string
}

variable "private_api_allowed_cidrs" {
  description = "VPN / runner CIDRs allowed to the private EKS endpoint."
  type        = list(string)
  default     = []
}

variable "transit_gateway_id" {
  description = "Shared TGW from the network account."
  type        = string
  default     = null
}

variable "customer_db_cidrs" {
  description = "Customer database networks reachable through the TGW (data-governance scans)."
  type        = list(string)
  default     = []
}

variable "flow_logs_destination_arn" {
  description = "Log Archive bucket ARN for VPC flow logs."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Permission boundary created by the landing zone."
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  description = "Monthly budget."
  type        = number
  default     = 8000
}
