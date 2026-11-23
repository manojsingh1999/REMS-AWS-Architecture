variable "alias" {
  description = "Alias name without the alias/ prefix, e.g. rems-prod-aurora."
  type        = string
}

variable "description" {
  description = "Key description."
  type        = string
}

variable "multi_region" {
  description = "Create a multi-Region primary key (required for DR replicas)."
  type        = bool
  default     = false
}

variable "primary_key_arn" {
  description = "If set, a replica of this multi-Region key is created instead of a new key."
  type        = string
  default     = null
}

variable "deletion_window_in_days" {
  description = "Waiting period before deletion."
  type        = number
  default     = 30
}

variable "key_administrator_arns" {
  description = "IAM principals allowed to administer the key."
  type        = list(string)
  default     = []
}

variable "key_user_arns" {
  description = "IAM principals allowed to use the key for crypto operations."
  type        = list(string)
  default     = []
}

variable "service_principals" {
  description = "AWS service principals allowed to use the key (e.g. logs.ap-south-1.amazonaws.com)."
  type        = list(string)
  default     = []
}

variable "restrict_service_principals_to_account" {
  description = "Add aws:SourceAccount = this account to service-principal grants (disable for org-wide services such as an organization CloudTrail)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
