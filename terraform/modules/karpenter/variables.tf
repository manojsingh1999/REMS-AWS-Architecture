variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "namespace" {
  description = "Namespace of the Karpenter controller."
  type        = string
  default     = "kube-system"
}

variable "service_account" {
  description = "Service account of the Karpenter controller."
  type        = string
  default     = "karpenter"
}

variable "permissions_boundary_arn" {
  description = "Permission boundary for created roles."
  type        = string
  default     = null
}

variable "ebs_kms_key_arn" {
  description = "CMK used for EBS default encryption (controller needs grant permissions)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
