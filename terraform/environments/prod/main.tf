module "rems" {
  source = "../../modules/rems-environment"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  environment = "prod"
  site        = "primary"
  azs         = var.azs

  # ---- network: 3 NAT gateways (one per AZ) for static stability
  vpc_cidr                  = "10.30.0.0/16"
  single_nat_gateway        = false
  transit_gateway_id        = var.transit_gateway_id
  transit_gateway_routes    = var.customer_db_cidrs
  flow_logs_destination_arn = var.flow_logs_destination_arn

  # ---- EKS: private endpoint only
  kubernetes_version        = "1.31"
  endpoint_public_access    = false
  private_api_allowed_cidrs = var.private_api_allowed_cidrs
  system_node_group = {
    instance_types = ["m7g.large"]
    min_size       = 3
    max_size       = 6
    desired_size   = 3
  }
  access_entries = {
    platform-admin = { principal_arn = var.platform_admin_role_arn, policy_name = "AmazonEKSClusterAdminPolicy" }
    readonly       = { principal_arn = var.readonly_role_arn, policy_name = "AmazonEKSViewPolicy" }
    oncall         = { principal_arn = var.oncall_role_arn, kubernetes_groups = ["rems-oncall"] }
    cicd           = { principal_arn = var.cicd_deploy_role_arn, policy_name = "AmazonEKSViewPolicy", namespaces = ["rems", "rems-ai", "argocd"] }
  }

  # ---- data tier
  aurora_core = {
    instance_class    = "db.r7g.2xlarge"
    reader_count      = 2
    io_optimized      = true
    autoscaling_max   = 5
    pi_retention_days = 731
  }
  aurora_rag = {
    instance_class    = "db.r7g.xlarge"
    reader_count      = 1
    io_optimized      = true
    autoscaling_max   = 3
    pi_retention_days = 31
  }
  redis = {
    node_type          = "cache.r7g.large"
    num_shards         = 3
    replicas_per_shard = 1
  }
  deletion_protection = true

  # ---- DR (Aurora Global DB, S3 CRR+RTC, secret replicas, backup copies)
  enable_dr_replication = true
  dr_region             = var.dr_region

  # ---- edge / identity
  domain_name           = var.domain_name
  hosted_zone_id        = var.hosted_zone_id
  cognito_domain_prefix = var.cognito_domain_prefix
  waf_rate_limit_per_ip = 6000

  # ---- ops
  telemetry_retention_days = 90
  alert_emails             = var.alert_emails
  monthly_budget_usd       = var.monthly_budget_usd
  kms_admin_arns           = [var.platform_admin_role_arn]
  permissions_boundary_arn = var.permissions_boundary_arn
  enable_fis               = true
}
