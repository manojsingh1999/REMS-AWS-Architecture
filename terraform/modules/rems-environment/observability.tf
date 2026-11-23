module "ai_platform" {
  source = "../ai-platform"

  name                = local.name
  environment         = var.environment
  allowed_model_ids   = var.allowed_model_ids
  secrets_kms_key_arn = module.kms["secrets"].key_arn
  logs_kms_key_arn    = module.kms["logs"].key_arn
  tags                = local.tags
}

module "monitoring" {
  source = "../monitoring"

  name                        = local.name
  environment                 = var.environment
  alert_emails                = var.alert_emails
  sns_kms_key_arn             = module.kms["sns"].key_arn
  logs_kms_key_arn            = module.kms["logs"].key_arn
  eks_cluster_name            = module.eks.cluster_name
  aurora_cluster_ids          = [module.aurora_core.cluster_id, module.aurora_rag.cluster_id]
  aurora_global_cluster_ids   = var.enable_dr_replication ? [module.aurora_core.cluster_id, module.aurora_rag.cluster_id] : []
  redis_replication_group_id  = module.redis.replication_group_id
  monthly_budget_usd          = var.monthly_budget_usd
  create_cost_anomaly_monitor = var.create_cost_anomaly_monitor
  tags                        = local.tags
}

# Container Insights (enhanced observability) feeds the out-of-band EKS alarms.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    containerLogs = { enabled = false } # application logs go to Loki; avoid paying twice
  })
  tags = local.tags
}

module "irsa_cloudwatch_agent" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-cloudwatch-agent"
  cluster_name             = module.eks.cluster_name
  namespace                = "amazon-cloudwatch"
  service_account          = "cloudwatch-agent"
  managed_policy_arns      = ["arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"]
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}
