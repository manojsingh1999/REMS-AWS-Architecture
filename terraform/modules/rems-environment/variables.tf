# ---------------------------------------------------------------- identity of the stack
variable "environment" {
  description = "dev | staging | prod"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "site" {
  description = "primary or dr (prod-dr stack uses dr)."
  type        = string
  default     = "primary"
  validation {
    condition     = contains(["primary", "dr"], var.site)
    error_message = "site must be primary or dr."
  }
}

variable "azs" {
  description = "Three AZs in the stack region."
  type        = list(string)
}

variable "tags" {
  description = "Extra tags (Owner, CostCenter...)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------- network
variable "vpc_cidr" {
  description = "/16 CIDR for the VPC."
  type        = string
}

variable "single_nat_gateway" {
  description = "One NAT gateway (dev only)."
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "Shared TGW ID from the network account (null = no attachment)."
  type        = string
  default     = null
}

variable "transit_gateway_routes" {
  description = "CIDRs reachable through the TGW (customer DB networks for data-governance)."
  type        = list(string)
  default     = []
}

variable "flow_logs_destination_arn" {
  description = "Log Archive bucket ARN for VPC flow logs (null = CloudWatch)."
  type        = string
  default     = null
}

# ---------------------------------------------------------------- EKS
variable "kubernetes_version" {
  description = "EKS version."
  type        = string
  default     = "1.31"
}

variable "endpoint_public_access" {
  description = "Public API endpoint (dev only)."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs for the public API endpoint."
  type        = list(string)
  default     = []
}

variable "private_api_allowed_cidrs" {
  description = "VPN / CI runner CIDRs allowed to the private API endpoint."
  type        = list(string)
  default     = []
}

variable "system_node_group" {
  description = "System node group sizing."
  type = object({
    instance_types = optional(list(string), ["m7g.large"])
    min_size       = optional(number, 3)
    max_size       = optional(number, 6)
    desired_size   = optional(number, 3)
  })
  default = {}
}

variable "access_entries" {
  description = "EKS access entries (Identity Center roles, CI roles)."
  type = map(object({
    principal_arn     = string
    policy_name       = optional(string)
    namespaces        = optional(list(string), [])
    kubernetes_groups = optional(list(string), [])
  }))
  default = {}
}

# ---------------------------------------------------------------- data tier
variable "aurora_core" {
  description = "rems-core Aurora cluster (API, authz, governance)."
  type = object({
    instance_class        = string
    reader_count          = optional(number, 2)
    io_optimized          = optional(bool, false)
    autoscaling_max       = optional(number, 5)
    pi_retention_days     = optional(number, 7)
    backup_retention_days = optional(number, 35)
  })
}

variable "aurora_rag" {
  description = "rems-rag Aurora cluster (Savvy / pgvector)."
  type = object({
    instance_class        = string
    reader_count          = optional(number, 1)
    io_optimized          = optional(bool, false)
    autoscaling_max       = optional(number, 3)
    pi_retention_days     = optional(number, 7)
    backup_retention_days = optional(number, 35)
  })
}

variable "redis" {
  description = "ElastiCache Valkey sizing."
  type = object({
    node_type          = string
    num_shards         = optional(number, 3)
    replicas_per_shard = optional(number, 1)
  })
}

variable "deletion_protection" {
  description = "Deletion protection for stateful resources."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------- DR
variable "enable_dr_replication" {
  description = "Primary prod only: Aurora Global DB, S3 CRR+RTC, secret replicas, DR backup vault."
  type        = bool
  default     = false
}

variable "dr_region" {
  description = "DR region (aws.dr provider must point here)."
  type        = string
  default     = "ap-southeast-1"
}

variable "global_cluster_ids" {
  description = "DR site only: { core = ..., rag = ... } global cluster identifiers from the primary stack."
  type        = map(string)
  default     = {}
}

variable "dr_kms_key_arns" {
  description = "DR site only: replica KMS key ARNs created by the primary stack (aurora, secrets, s3)."
  type        = map(string)
  default     = {}
}

variable "dr_promoted" {
  description = "DR site only: true after the secondary has been promoted (creates RDS Proxy, scales up)."
  type        = bool
  default     = false
}

variable "dr_proxy_secret_arns" {
  description = "DR site only: replica secret ARNs used by the RDS Proxy after promotion ({ core = [...], rag = [...] })."
  type        = map(list(string))
  default     = {}
}

# ---------------------------------------------------------------- edge / identity
variable "domain_name" {
  description = "Base domain, e.g. rems.example.com (PLACEHOLDER)."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 public hosted zone ID for ACM validation (null = skip ACM)."
  type        = string
  default     = null
}

variable "cognito_domain_prefix" {
  description = "Globally unique Cognito hosted UI prefix."
  type        = string
}

variable "waf_rate_limit_per_ip" {
  description = "WAF requests per 5 minutes per IP."
  type        = number
  default     = 6000
}

# ---------------------------------------------------------------- AI
variable "allowed_model_ids" {
  description = "Bedrock model IDs / inference profile ARNs the LLM gateway may call."
  type        = list(string)
  default = [
    "anthropic.claude-3-5-sonnet-20240620-v1:0",
    "anthropic.claude-3-haiku-20240307-v1:0",
    "amazon.titan-embed-text-v2:0",
  ]
}

# ---------------------------------------------------------------- ops
variable "telemetry_retention_days" {
  description = "Loki/Tempo object expiry (PDF: 30-90 days)."
  type        = number
  default     = 90
}

variable "alert_emails" {
  description = "Alert subscribers."
  type        = list(string)
  default     = []
}

variable "monthly_budget_usd" {
  description = "Monthly budget for the environment."
  type        = number
}

variable "create_cost_anomaly_monitor" {
  description = "Create Cost Anomaly Detection monitor in this account."
  type        = bool
  default     = true
}

variable "kms_admin_arns" {
  description = "Key administrators (platform admin role)."
  type        = list(string)
  default     = []
}

variable "permissions_boundary_arn" {
  description = "Permission boundary for all workload/IAM roles (created by landing zone)."
  type        = string
  default     = null
}

variable "enable_fis" {
  description = "Create the AWS FIS role for AZ/chaos experiments."
  type        = bool
  default     = false
}
