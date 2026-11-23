variable "name" {
  description = "User pool name."
  type        = string
}

variable "domain_prefix" {
  description = "Hosted UI domain prefix (globally unique per region)."
  type        = string
}

variable "callback_urls" {
  description = "Web app OAuth callback URLs."
  type        = list(string)
}

variable "logout_urls" {
  description = "Web app logout URLs."
  type        = list(string)
}

variable "mcp_callback_urls" {
  description = "MCP client callback URLs (localhost loopback for IDE clients)."
  type        = list(string)
  default     = ["http://localhost:33418/callback"]
}

variable "supported_identity_providers" {
  description = "COGNITO plus federated IdP names added per tenant."
  type        = list(string)
  default     = ["COGNITO"]
}

variable "pre_token_generation_lambda_arn" {
  description = "Lambda that injects tenant_id/roles claims (null to skip)."
  type        = string
  default     = null
}

variable "advanced_security_mode" {
  description = "OFF | AUDIT | ENFORCED (threat protection)."
  type        = string
  default     = "AUDIT"
}

variable "deletion_protection" {
  description = "Protect the user pool."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
