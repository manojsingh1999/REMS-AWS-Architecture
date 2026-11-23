variable "name" {
  description = "Replication group ID, e.g. rems-prod-cache."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "engine" {
  description = "valkey or redis."
  type        = string
  default     = "valkey"
}

variable "engine_version" {
  description = "Engine version."
  type        = string
  default     = "7.2"
}

variable "parameter_group_family" {
  description = "Parameter group family matching the engine (valkey7 / redis7)."
  type        = string
  default     = "valkey7"
}

variable "node_type" {
  description = "Node type (cache.r7g.large for prod)."
  type        = string
}

variable "cluster_mode" {
  description = "Enable cluster mode (sharding)."
  type        = bool
  default     = true
}

variable "num_shards" {
  description = "Shards when cluster mode is enabled."
  type        = number
  default     = 3
}

variable "replicas_per_shard" {
  description = "Replicas per shard (>=1 enables Multi-AZ automatic failover)."
  type        = number
  default     = 1
}

variable "maxmemory_policy" {
  description = "Eviction policy. volatile-lru protects queue keys without TTL."
  type        = string
  default     = "volatile-lru"
}

variable "snapshot_retention_days" {
  description = "Daily snapshot retention."
  type        = number
  default     = 7
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "private-data subnet IDs."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Client SGs."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for at-rest encryption."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key for the AUTH secret."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for slow-log group."
  type        = string
  default     = null
}

variable "secret_replica_regions" {
  description = "Replicate the AUTH secret (DR)."
  type = list(object({
    region      = string
    kms_key_arn = string
  }))
  default = []
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
