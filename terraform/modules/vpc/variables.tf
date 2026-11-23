variable "name" {
  description = "VPC name prefix."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. Must be a /16 for the built-in subnet plan."
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && endswith(var.cidr_block, "/16")
    error_message = "cidr_block must be a valid /16."
  }
}

variable "azs" {
  description = "Exactly three availability zones."
  type        = list(string)
  validation {
    condition     = length(var.azs) == 3
    error_message = "REMS requires three AZs for 99.95% availability."
  }
}

variable "cluster_name" {
  description = "EKS cluster name used for Karpenter discovery tags."
  type        = string
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway (cost saving for dev). Prod must be false."
  type        = bool
  default     = false
}

variable "interface_endpoints" {
  description = "Interface VPC endpoint service suffixes."
  type        = list(string)
  default = [
    "ecr.api", "ecr.dkr", "sts", "kms", "secretsmanager", "logs", "monitoring",
    "ssm", "ssmmessages", "ec2messages", "ec2", "elasticloadbalancing", "eks", "eks-auth",
    "sqs", "bedrock-runtime"
  ]
}

variable "transit_gateway_id" {
  description = "Shared Transit Gateway ID (from the network account). Null disables the attachment."
  type        = string
  default     = null
}

variable "transit_gateway_routes" {
  description = "CIDRs routed to the TGW from app subnets (customer DB networks, shared services)."
  type        = list(string)
  default     = []
}

variable "flow_logs_destination_arn" {
  description = "S3 bucket ARN in the Log Archive account. Null = CloudWatch Logs in this account."
  type        = string
  default     = null
}

variable "flow_logs_retention_days" {
  description = "Retention when flow logs go to CloudWatch."
  type        = number
  default     = 90
}

variable "logs_kms_key_arn" {
  description = "KMS key for the flow log group."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
