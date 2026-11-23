variable "account_id" {
  description = "Prod account ID (DR runs in the same account, different region)."
  type        = string
}

variable "region" {
  description = "DR region."
  type        = string
  default     = "ap-southeast-1"
}

variable "primary_region" {
  description = "Primary region (for remote state and ARN rewriting)."
  type        = string
  default     = "ap-south-1"
}

variable "azs" {
  description = "Three AZs in the DR region."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
}

variable "prod_state_bucket" {
  description = "State bucket of the primary prod stack."
  type        = string
}

variable "prod_state_region" {
  description = "Region of prod_state_bucket (set to the DR region and point prod_state_bucket at the replica during a primary outage)."
  type        = string
  default     = null
}

variable "dr_promoted" {
  description = "Set to true during regional failover after the Aurora secondaries are promoted."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Public domain."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID."
  type        = string
  default     = null
}

variable "cognito_domain_prefix" {
  description = "Cognito prefix for the DR user pool."
  type        = string
}

variable "alert_emails" {
  description = "On-call lists."
  type        = list(string)
  default     = []
}

variable "platform_admin_role_arn" {
  description = "PlatformAdmin role ARN."
  type        = string
}

variable "readonly_role_arn" {
  description = "ReadOnly role ARN."
  type        = string
}

variable "private_api_allowed_cidrs" {
  description = "VPN CIDRs."
  type        = list(string)
  default     = []
}

variable "flow_logs_destination_arn" {
  description = "Log Archive bucket ARN."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Permission boundary."
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  description = "Budget for the DR site."
  type        = number
  default     = 9000
}
