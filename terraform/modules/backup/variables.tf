variable "name" {
  description = "Vault/plan name."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for the vault."
  type        = string
}

variable "create_plan" {
  description = "Create plan + selection (false for a copy-target-only vault in DR)."
  type        = bool
  default     = true
}

variable "dr_vault_arn" {
  description = "Cross-region copy destination vault ARN."
  type        = string
  default     = null
}

variable "daily_retention_days" {
  description = "Daily backup retention."
  type        = number
  default     = 35
}

variable "enable_vault_lock" {
  description = "Enable AWS Backup Vault Lock."
  type        = bool
  default     = true
}

variable "min_retention_days" {
  description = "Vault Lock minimum retention."
  type        = number
  default     = 7
}

variable "max_retention_days" {
  description = "Vault Lock maximum retention."
  type        = number
  default     = 400
}

variable "lock_changeable_for_days" {
  description = "Grace period before the lock becomes immutable (compliance mode). Null = governance mode."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
