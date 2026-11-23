variable "name" {
  description = "Name prefix (e.g. rems-prod)."
  type        = string
}

variable "environment" {
  description = "Environment."
  type        = string
}

variable "alert_emails" {
  description = "Email subscribers for the alert topic."
  type        = list(string)
  default     = []
}

variable "pagerduty_endpoint" {
  description = "PagerDuty (or Opsgenie) HTTPS integration URL. Stored in tfvars kept out of Git or via TF_VAR_."
  type        = string
  default     = null
  sensitive   = true
}

variable "sns_kms_key_arn" {
  description = "KMS key for the SNS topic."
  type        = string
  default     = null
}

variable "logs_kms_key_arn" {
  description = "KMS key for the audit log group."
  type        = string
  default     = null
}

variable "eks_cluster_name" {
  description = "EKS cluster name (Container Insights dimension)."
  type        = string
}

variable "aurora_cluster_ids" {
  description = "Aurora cluster identifiers to alarm on."
  type        = list(string)
  default     = []
}

variable "aurora_global_cluster_ids" {
  description = "Primary clusters participating in a Global Database (lag alarm)."
  type        = list(string)
  default     = []
}

variable "aurora_connections_threshold" {
  description = "Alarm when connections exceed this."
  type        = number
  default     = 1500
}

variable "redis_replication_group_id" {
  description = "ElastiCache replication group ID."
  type        = string
  default     = null
}

variable "authz_deny_threshold" {
  description = "Denied decisions per 5 minutes that trigger a security alert."
  type        = number
  default     = 50
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for this environment."
  type        = number
}

variable "create_cost_anomaly_monitor" {
  description = "Create a Cost Anomaly Detection monitor (one per account is enough)."
  type        = bool
  default     = true
}

variable "cost_anomaly_threshold_usd" {
  description = "Absolute anomaly impact (USD) that triggers notification."
  type        = number
  default     = 100
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
