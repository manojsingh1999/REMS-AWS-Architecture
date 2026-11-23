variable "role_name" {
  description = "IAM role name."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account."
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account name."
  type        = string
}

variable "policy_json" {
  description = "Inline least-privilege policy JSON (null = none)."
  type        = string
  default     = null
}

variable "managed_policy_arns" {
  description = "Managed policies to attach."
  type        = list(string)
  default     = []
}

variable "permissions_boundary_arn" {
  description = "Permission boundary ARN."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
