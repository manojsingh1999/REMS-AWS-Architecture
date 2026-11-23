output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "app_subnets_by_az" {
  description = "App subnets per AZ (FIS experiments)."
  value       = module.vpc.app_subnets_by_az
}

output "nat_public_ips" {
  description = "Egress IPs."
  value       = module.vpc.nat_public_ips
}

output "karpenter" {
  description = "Values for the Karpenter Helm chart and EC2NodeClass."
  value = {
    node_role_name     = module.karpenter.node_role_name
    interruption_queue = module.karpenter.interruption_queue_name
  }
}

output "aurora" {
  description = "Aurora endpoints and secrets."
  value = {
    core_proxy_endpoint    = module.aurora_core.proxy_endpoint
    core_proxy_ro_endpoint = module.aurora_core.proxy_read_only_endpoint
    core_cluster_id        = module.aurora_core.cluster_id
    core_global_id         = module.aurora_core.global_cluster_id
    rag_proxy_endpoint     = module.aurora_rag.proxy_endpoint
    rag_proxy_ro_endpoint  = module.aurora_rag.proxy_read_only_endpoint
    rag_cluster_id         = module.aurora_rag.cluster_id
    rag_global_id          = module.aurora_rag.global_cluster_id
    secret_names           = merge(module.aurora_core.service_secret_names, module.aurora_rag.service_secret_names)
    core_secret_arns       = values(module.aurora_core.service_secret_arns)
    rag_secret_arns        = values(module.aurora_rag.service_secret_arns)
  }
}

output "redis" {
  description = "Redis endpoint and AUTH secret."
  value = {
    endpoint    = module.redis.endpoint
    secret_name = module.redis.auth_secret_name
  }
}

output "buckets" {
  description = "S3 bucket names."
  value = {
    documents = module.s3_documents.bucket_id
    telemetry = module.s3_telemetry.bucket_id
    alb_logs  = module.s3_alb_logs.bucket_id
  }
}

output "edge" {
  description = "Values for ALB Ingress annotations."
  value = {
    waf_acl_arn     = module.waf.web_acl_arn
    certificate_arn = var.hosted_zone_id == null ? null : aws_acm_certificate_validation.this[0].certificate_arn
  }
}

output "cognito" {
  description = "OIDC settings for services."
  value = {
    issuer_url    = module.cognito.issuer_url
    web_client_id = module.cognito.web_client_id
    mcp_client_id = module.cognito.mcp_client_id
  }
}

output "ai" {
  description = "Bedrock guardrail and provider key secrets."
  value = {
    guardrail_id          = module.ai_platform.guardrail_id
    guardrail_version     = module.ai_platform.guardrail_version
    provider_secret_names = module.ai_platform.provider_secret_names
  }
}

output "alerts_topic_arn" {
  description = "SNS alert topic."
  value       = module.monitoring.alerts_topic_arn
}

output "dr" {
  description = "Inputs for the prod-dr stack."
  value = var.enable_dr_replication ? {
    kms_key_arns       = { for k, m in module.kms_dr : k => m.key_arn }
    global_cluster_ids = { core = module.aurora_core.global_cluster_id, rag = module.aurora_rag.global_cluster_id }
    documents_bucket   = module.s3_documents_dr[0].bucket_id
    backup_vault_arn   = module.backup_dr_vault[0].vault_arn
  } : null
}

output "fis_role_arn" {
  description = "FIS experiment role."
  value       = var.enable_fis ? aws_iam_role.fis[0].arn : null
}
