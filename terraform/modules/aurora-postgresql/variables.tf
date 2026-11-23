variable "name" {
  description = "Cluster identifier, e.g. rems-prod-core."
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)."
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL version (pgvector >= 0.7 available on 16.x)."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Instance class (db.r7g.* for prod, db.serverless allowed for dev)."
  type        = string
}

variable "reader_count" {
  description = "Number of reader instances managed by Terraform (auto scaling may add more)."
  type        = number
  default     = 2
}

variable "azs" {
  description = "AZs used to spread instances."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "private-data subnet IDs."
  type        = list(string)
}

variable "proxy_subnet_ids" {
  description = "Subnets for RDS Proxy ENIs (private-data)."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Client SGs allowed to connect (EKS cluster SG)."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for storage and Performance Insights."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key for Secrets Manager secrets."
  type        = string
}

variable "secret_replica_regions" {
  description = "Replicate DB secrets to these regions (DR)."
  type = list(object({
    region      = string
    kms_key_arn = string
  }))
  default = []
}

variable "master_username" {
  description = "Master username (break-glass only)."
  type        = string
  default     = "rems_admin"
}

variable "service_users" {
  description = "Per-service DB logins: key => { username, database }."
  type = map(object({
    username = string
    database = string
  }))
  default = {}
}

variable "backup_retention_days" {
  description = "Continuous backup / PITR window (max 35)."
  type        = number
  default     = 35
}

variable "deletion_protection" {
  description = "Protect against deletion (true for staging/prod)."
  type        = bool
  default     = true
}

variable "io_optimized" {
  description = "Use Aurora I/O-Optimized storage (cheaper when I/O > ~25% of DB spend)."
  type        = bool
  default     = false
}

variable "serverless_min_acu" {
  description = "Serverless v2 minimum ACUs (only used by db.serverless instances)."
  type        = number
  default     = 0.5
}

variable "serverless_max_acu" {
  description = "Serverless v2 maximum ACUs."
  type        = number
  default     = 16
}

variable "performance_insights_retention_days" {
  description = "7 (free) or 31*n up to 731."
  type        = number
  default     = 7
}

variable "slow_query_ms" {
  description = "log_min_duration_statement in ms."
  type        = number
  default     = 500
}

variable "statement_timeout_ms" {
  description = "Server-side statement timeout guardrail."
  type        = number
  default     = 30000
}

variable "reader_autoscaling" {
  description = "Aurora replica auto scaling."
  type = object({
    enabled    = optional(bool, true)
    min        = optional(number, 2)
    max        = optional(number, 5)
    target_cpu = optional(number, 60)
  })
  default = {}
}

variable "global_role" {
  description = "none | primary (creates an Aurora Global Database) | secondary (joins one)."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "primary", "secondary"], var.global_role)
    error_message = "global_role must be none, primary or secondary."
  }
}

variable "global_cluster_identifier" {
  description = "Existing global cluster ID (required when global_role = secondary)."
  type        = string
  default     = null
}

variable "enable_proxy" {
  description = "Create RDS Proxy (in DR this is enabled only after promotion)."
  type        = bool
  default     = true
}

variable "proxy_iam_auth" {
  description = "RDS Proxy client IAM auth: REQUIRED or DISABLED (DISABLED until services support IAM tokens)."
  type        = string
  default     = "DISABLED"
}

variable "proxy_secret_arns" {
  description = "Secret ARNs for the proxy when this cluster is a promoted secondary (replica secrets)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
