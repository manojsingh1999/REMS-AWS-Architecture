variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version."
  type        = string
  default     = "1.31"
}

variable "support_type" {
  description = "EKS upgrade policy: STANDARD or EXTENDED."
  type        = string
  default     = "STANDARD"
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "control_plane_subnet_ids" {
  description = "Subnets for EKS control-plane ENIs (intra subnets)."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets for worker nodes (private-app)."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API publicly (dev only, restricted by CIDR)."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint."
  type        = list(string)
  default     = []
}

variable "private_api_allowed_cidrs" {
  description = "Private CIDRs (VPN, CI runners) allowed to reach the private API endpoint."
  type        = list(string)
  default     = []
}

variable "secrets_kms_key_arn" {
  description = "KMS key ARN for envelope encryption of Kubernetes Secrets."
  type        = string
}

variable "ebs_kms_key_arn" {
  description = "KMS key ARN for node EBS volumes and the EBS CSI driver."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key ARN for the control-plane log group."
  type        = string
  default     = null
}

variable "control_plane_log_retention_days" {
  description = "Retention for control-plane logs."
  type        = number
  default     = 90
}

variable "permissions_boundary_arn" {
  description = "Permission boundary attached to all IAM roles created by this module."
  type        = string
  default     = null
}

variable "system_node_group" {
  description = "Managed node group that hosts cluster-critical controllers."
  type = object({
    instance_types = optional(list(string), ["m7g.large"])
    ami_type       = optional(string, "AL2023_ARM_64_STANDARD")
    min_size       = optional(number, 3)
    max_size       = optional(number, 6)
    desired_size   = optional(number, 3)
    disk_size_gb   = optional(number, 50)
  })
  default = {}
}

variable "addon_versions" {
  description = "Pin add-on versions (null/absent = latest default for the cluster version)."
  type        = map(string)
  default     = {}
}

variable "access_entries" {
  description = "EKS access entries: key => { principal_arn, policy_name, namespaces, kubernetes_groups }."
  type = map(object({
    principal_arn = string
    policy_name       = optional(string)                # EKS access policy (null = RBAC groups only)
    namespaces        = optional(list(string), [])
    kubernetes_groups = optional(list(string), [])      # bound by ClusterRoleBindings, e.g. rems-oncall
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
