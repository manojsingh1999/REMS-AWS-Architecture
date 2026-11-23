module "rems" {
  source = "../../modules/rems-environment"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  environment = "dev"
  site        = "primary"
  azs         = var.azs

  # ---- network: single NAT to save cost (dev accepts AZ-level egress risk)
  vpc_cidr                  = "10.10.0.0/16"
  single_nat_gateway        = true
  transit_gateway_id        = var.transit_gateway_id
  transit_gateway_routes    = var.customer_db_cidrs
  flow_logs_destination_arn = var.flow_logs_destination_arn

  # ---- EKS: public endpoint restricted to developer CIDRs
  kubernetes_version           = "1.31"
  endpoint_public_access       = length(var.endpoint_public_access_cidrs) > 0
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  private_api_allowed_cidrs    = var.private_api_allowed_cidrs
  system_node_group = {
    instance_types = ["t4g.large"]
    min_size       = 2
    max_size       = 3
    desired_size   = 2
  }
  access_entries = {
    platform-admin = { principal_arn = var.platform_admin_role_arn, policy_name = "AmazonEKSClusterAdminPolicy" }
    readonly       = { principal_arn = var.readonly_role_arn, policy_name = "AmazonEKSViewPolicy" }
    cicd           = { principal_arn = var.cicd_deploy_role_arn, policy_name = "AmazonEKSEditPolicy", namespaces = ["rems", "rems-ai"] }
  }

  # ---- data tier: Aurora Serverless v2 scales to 0.5 ACU when idle
  aurora_core = {
    instance_class        = "db.serverless"
    reader_count          = 0
    autoscaling_max       = 1
    backup_retention_days = 7
  }
  aurora_rag = {
    instance_class        = "db.serverless"
    reader_count          = 0
    autoscaling_max       = 1
    backup_retention_days = 7
  }
  redis = {
    node_type          = "cache.t4g.small"
    num_shards         = 1
    replicas_per_shard = 1 # cluster mode requires automatic failover; keeps client parity with prod
  }
  deletion_protection = false

  enable_dr_replication = false

  domain_name           = var.domain_name
  hosted_zone_id        = var.hosted_zone_id
  cognito_domain_prefix = var.cognito_domain_prefix
  waf_rate_limit_per_ip = 3000

  telemetry_retention_days = 30
  alert_emails             = var.alert_emails
  monthly_budget_usd       = var.monthly_budget_usd
  kms_admin_arns           = [var.platform_admin_role_arn]
  permissions_boundary_arn = var.permissions_boundary_arn
  enable_fis               = false
}
