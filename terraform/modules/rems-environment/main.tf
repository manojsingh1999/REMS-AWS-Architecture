data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  name         = var.site == "dr" ? "rems-${var.environment}-dr" : "rems-${var.environment}"
  cluster_name = local.name
  is_dr        = var.site == "dr"

  tags = merge(var.tags, {
    Project     = "REMS"
    Environment = var.environment
    Site        = var.site
    ManagedBy   = "terraform"
  })

  # Kubernetes namespaces (must match kubernetes/base/namespaces.yaml)
  ns = {
    app    = "rems"
    ai     = "rems-ai"
    obs    = "observability"
    mon    = "monitoring"
    eso    = "external-secrets"
    system = "kube-system"
    dns    = "external-dns"
  }

  aurora_global_role = local.is_dr ? "secondary" : (var.enable_dr_replication ? "primary" : "none")

  # ALB access log delivery accounts (regions launched before Aug 2022).
  elb_log_accounts = {
    "ap-south-1"     = "718504428378"
    "ap-southeast-1" = "114774131450"
    "us-east-1"      = "127311923021"
    "eu-west-1"      = "156460612806"
  }
}

# Encrypt every new EBS volume in the account/region by default with our CMK.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  key_arn = module.kms["ebs"].key_arn
}
