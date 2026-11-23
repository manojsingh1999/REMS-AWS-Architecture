module "rems" {
  source = "../../modules/rems-environment"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  environment = "staging"
  site        = "primary"
  azs         = var.azs

  # ---- network: production-like topology (3 NAT) so AZ-failure drills are meaningful
  vpc_cidr                  = "10.20.0.0/16"
  single_nat_gateway        = false
  transit_gateway_id        = var.transit_gateway_id
  transit_gateway_routes    = var.customer_db_cidrs
  flow_logs_destination_arn = var.flow_logs_destination_arn

  kubernetes_version        = "1.31"
  endpoint_public_access    = false
  private_api_allowed_cidrs = var.private_api_allowed_cidrs
  system_node_group = {
    instance_types = ["m7g.large"]
    min_size       = 3
    max_size       = 4
    desired_size   = 3
  }
  access_entries = {
    platform-admin = { principal_arn = var.platform_admin_role_arn, policy_name = "AmazonEKSClusterAdminPolicy" }
    readonly       = { principal_arn = var.readonly_role_arn, policy_name = "AmazonEKSViewPolicy" }
    oncall         = { principal_arn = var.oncall_role_arn, kubernetes_groups = ["rems-oncall"] }
    cicd           = { principal_arn = var.cicd_deploy_role_arn, policy_name = "AmazonEKSViewPolicy", namespaces = ["rems", "rems-ai", "argocd"] }
  }

  aurora_core = {
    instance_class        = "db.r7g.large"
    reader_count          = 1
    autoscaling_max       = 2
    backup_retention_days = 14
  }
  aurora_rag = {
    instance_class        = "db.r7g.large"
    reader_count          = 1
    autoscaling_max       = 2
    backup_retention_days = 14
  }
  redis = {
    node_type          = "cache.r7g.large"
    num_shards         = 2
    replicas_per_shard = 1
  }
  deletion_protection = true

  enable_dr_replication = false

  domain_name           = var.domain_name
  hosted_zone_id        = var.hosted_zone_id
  cognito_domain_prefix = var.cognito_domain_prefix
  waf_rate_limit_per_ip = 6000

  telemetry_retention_days = 30
  alert_emails             = var.alert_emails
  monthly_budget_usd       = var.monthly_budget_usd
  kms_admin_arns           = [var.platform_admin_role_arn]
  permissions_boundary_arn = var.permissions_boundary_arn
  enable_fis               = true
}
