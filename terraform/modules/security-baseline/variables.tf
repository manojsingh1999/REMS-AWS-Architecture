variable "is_aggregation_region" {
  description = "True in the home region (Security Hub + Config aggregation)."
  type        = bool
  default     = true
}

variable "security_emails" {
  description = "Security team distribution lists."
  type        = list(string)
  default     = []
}

variable "sns_kms_key_arn" {
  description = "KMS key for the findings topic (must allow events.amazonaws.com)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
