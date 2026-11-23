# Warm-standby DR site in ap-southeast-1.
# Normal state : dr_promoted = false -> Aurora secondaries (read-only), minimal EKS, no RDS Proxy.
# Failover     : runbooks/dr-regional-failover.md -> promote Aurora, set dr_promoted = true, apply.

data "terraform_remote_state" "prod" {
  backend = "s3"
  config = {
    bucket = var.prod_state_bucket
    key    = "rems/prod/primary/terraform.tfstate"
    region = coalesce(var.prod_state_region, var.primary_region)
  }
}

locals {
  prod_dr = data.terraform_remote_state.prod.outputs.dr

  # Replica secrets keep the primary name/ARN suffix; only the region differs.
  dr_proxy_secret_arns = {
    core = [for a in data.terraform_remote_state.prod.outputs.aurora.core_secret_arns : replace(a, ":${var.primary_region}:", ":${var.region}:")]
    rag  = [for a in data.terraform_remote_state.prod.outputs.aurora.rag_secret_arns : replace(a, ":${var.primary_region}:", ":${var.region}:")]
  }
}

module "rems" {
  source = "../../modules/rems-environment"

  providers = {
    aws    = aws
    aws.dr = aws
  }

  environment = "prod"
  site        = "dr"
  azs         = var.azs

  vpc_cidr                  = "10.40.0.0/16"
  single_nat_gateway        = false
  flow_logs_destination_arn = var.flow_logs_destination_arn

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
  }

  # Same classes as primary so a promoted cluster can carry production load.
  aurora_core = {
    instance_class    = "db.r7g.2xlarge"
    reader_count      = 2
    io_optimized      = true
    autoscaling_max   = 5
    pi_retention_days = 7
  }
  aurora_rag = {
    instance_class    = "db.r7g.xlarge"
    reader_count      = 1
    io_optimized      = true
    autoscaling_max   = 3
    pi_retention_days = 7
  }
  redis = {
    node_type          = "cache.r7g.large"
    num_shards         = 3
    replicas_per_shard = 1
  }
  deletion_protection = true

  global_cluster_ids   = local.prod_dr.global_cluster_ids
  dr_kms_key_arns      = local.prod_dr.kms_key_arns
  dr_promoted          = var.dr_promoted
  dr_proxy_secret_arns = local.dr_proxy_secret_arns

  domain_name           = var.domain_name
  hosted_zone_id        = var.hosted_zone_id
  cognito_domain_prefix = var.cognito_domain_prefix

  telemetry_retention_days    = 30
  alert_emails                = var.alert_emails
  monthly_budget_usd          = var.monthly_budget_usd
  create_cost_anomaly_monitor = false # one per account, created by the primary stack
  kms_admin_arns              = [var.platform_admin_role_arn]
  permissions_boundary_arn    = var.permissions_boundary_arn
  enable_fis                  = false
}
