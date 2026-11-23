output "cluster_name" {
  description = "EKS cluster name."
  value       = module.rems.cluster_name
}

output "karpenter" {
  description = "Karpenter settings."
  value       = module.rems.karpenter
}

output "aurora" {
  description = "Aurora endpoints and secrets."
  value       = module.rems.aurora
}

output "redis" {
  description = "Redis endpoint and secret."
  value       = module.rems.redis
}

output "buckets" {
  description = "Buckets."
  value       = module.rems.buckets
}

output "edge" {
  description = "WAF / ACM for ingress annotations."
  value       = module.rems.edge
}

output "cognito" {
  description = "OIDC settings."
  value       = module.rems.cognito
}

output "ai" {
  description = "AI platform outputs."
  value       = module.rems.ai
}

output "dr" {
  description = "Consumed by environments/prod-dr via terraform_remote_state."
  value       = module.rems.dr
}

output "app_subnets_by_az" {
  description = "For FIS AZ experiments."
  value       = module.rems.app_subnets_by_az
}

output "fis_role_arn" {
  description = "FIS role."
  value       = module.rems.fis_role_arn
}
