variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for SSE-KMS. Null = SSE-S3 (required for ALB access logs)."
  type        = string
  default     = null
}

variable "versioning" {
  description = "Enable versioning."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow destroy with objects (dev only)."
  type        = bool
  default     = false
}

variable "object_lock" {
  description = "Default Object Lock retention ({ mode = GOVERNANCE|COMPLIANCE, days })."
  type = object({
    mode = string
    days = number
  })
  default = null
}

variable "lifecycle_rules" {
  description = "Lifecycle rules."
  type = list(object({
    id                         = string
    prefix                     = optional(string, "")
    transitions                = optional(list(object({ days = number, storage_class = string })), [])
    expiration_days            = optional(number)
    noncurrent_expiration_days = optional(number, 30)
  }))
  default = []
}

variable "access_log_bucket" {
  description = "Target bucket for server access logs."
  type        = string
  default     = null
}

variable "additional_policy_json" {
  description = "Extra bucket policy statements merged with the TLS-only baseline."
  type        = string
  default     = null
}

variable "replication" {
  description = "Cross-region replication target ({ destination_bucket_arn, destination_kms_key_arn, rtc })."
  type = object({
    destination_bucket_arn  = string
    destination_kms_key_arn = string
    rtc                     = optional(bool, true)
  })
  default = null
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
