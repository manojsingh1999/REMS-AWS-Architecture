variable "namespace" {
  description = "Repository namespace prefix."
  type        = string
  default     = "rems"
}

variable "repositories" {
  description = "Repository names (one per deployable image)."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for image encryption."
  type        = string
}

variable "keep_image_count" {
  description = "Number of sha-* tagged images to keep per repo."
  type        = number
  default     = 50
}

variable "pull_account_ids" {
  description = "AWS accounts allowed to pull images."
  type        = list(string)
  default     = []
}

variable "replication_regions" {
  description = "Regions to replicate images to (DR)."
  type        = list(string)
  default     = []
}

variable "registry_account_id" {
  description = "Account ID that owns the registry (destination registry for same-account replication)."
  type        = string
}

variable "manage_registry_scanning" {
  description = "Manage registry-level enhanced scanning configuration."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
