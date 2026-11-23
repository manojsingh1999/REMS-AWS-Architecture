variable "name" {
  description = "Web ACL name."
  type        = string
}

variable "rate_limit_per_ip" {
  description = "Requests per 5 minutes per IP before blocking."
  type        = number
  default     = 6000
}

variable "rate_limit_auth_per_ip" {
  description = "Requests per 5 minutes per IP on auth paths."
  type        = number
  default     = 300
}

variable "auth_path_prefix" {
  description = "Path prefix for auth endpoints (PLACEHOLDER until the API routes are confirmed)."
  type        = string
  default     = "/api/auth"
}

variable "blocked_country_codes" {
  description = "ISO country codes to block (empty = none)."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "WAF log retention."
  type        = number
  default     = 90
}

variable "logs_kms_key_arn" {
  description = "KMS key for WAF logs."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
