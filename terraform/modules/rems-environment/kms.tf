locals {
  kms_keys = {
    eks         = { description = "EKS Kubernetes secrets envelope encryption", services = [] }
    ebs         = { description = "EBS volumes (nodes, PVs)", services = [] }
    aurora      = { description = "Aurora storage, snapshots, Performance Insights", services = [] }
    elasticache = { description = "ElastiCache at-rest encryption", services = [] }
    s3          = { description = "S3 documents and telemetry buckets", services = [] }
    secrets     = { description = "Secrets Manager", services = [] }
    logs        = { description = "CloudWatch Logs", services = ["logs.${local.region}.amazonaws.com"] }
    sns         = { description = "SNS alert topics", services = ["cloudwatch.amazonaws.com", "events.amazonaws.com", "budgets.amazonaws.com", "costalerts.amazonaws.com"] }
    backup      = { description = "AWS Backup vault", services = [] }
  }
}

module "kms" {
  source   = "../kms"
  for_each = local.kms_keys

  alias                  = "${local.name}-${each.key}"
  description            = "REMS ${local.name}: ${each.value.description}"
  service_principals     = each.value.services
  key_administrator_arns = var.kms_admin_arns
  tags                   = local.tags
}

# ---------------------------------------------------------------- DR-region keys (primary prod only)
module "kms_dr" {
  source    = "../kms"
  for_each  = var.enable_dr_replication ? toset(["aurora", "secrets", "s3", "backup"]) : toset([])
  providers = { aws = aws.dr }

  alias                  = "${local.name}-dr-${each.key}"
  description            = "REMS ${local.name} DR-region ${each.key} key"
  key_administrator_arns = var.kms_admin_arns
  tags                   = local.tags
}
