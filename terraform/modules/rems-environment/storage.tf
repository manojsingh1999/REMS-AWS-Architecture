# ---------------------------------------------------------------- RAG documents (critical: CRR + RTC to DR)
module "s3_documents" {
  source = "../s3-bucket"

  bucket_name   = "${local.name}-rag-documents-${local.account_id}"
  kms_key_arn   = module.kms["s3"].key_arn
  force_destroy = !var.deletion_protection

  lifecycle_rules = [{
    id                         = "tiering"
    transitions                = [{ days = 30, storage_class = "STANDARD_IA" }, { days = 180, storage_class = "GLACIER_IR" }]
    noncurrent_expiration_days = 90
  }]

  replication = var.enable_dr_replication ? {
    destination_bucket_arn  = module.s3_documents_dr[0].bucket_arn
    destination_kms_key_arn = module.kms_dr["s3"].key_arn
    rtc                     = true
  } : null

  tags = merge(local.tags, { backup = "rems-critical", DataClass = "tenant-confidential" })
}

module "s3_documents_dr" {
  source    = "../s3-bucket"
  count     = var.enable_dr_replication ? 1 : 0
  providers = { aws = aws.dr }

  bucket_name = "${local.name}-rag-documents-dr-${local.account_id}"
  kms_key_arn = module.kms_dr["s3"].key_arn
  tags        = merge(local.tags, { DataClass = "tenant-confidential", Site = "dr" })
}

# ---------------------------------------------------------------- Telemetry (Loki chunks, Tempo blocks, VM backups)
module "s3_telemetry" {
  source = "../s3-bucket"

  bucket_name   = "${local.name}-telemetry-${local.account_id}"
  kms_key_arn   = module.kms["s3"].key_arn
  versioning    = false
  force_destroy = !var.deletion_protection

  lifecycle_rules = [
    {
      id                         = "loki"
      prefix                     = "loki/"
      transitions                = [{ days = 30, storage_class = "STANDARD_IA" }]
      expiration_days            = var.telemetry_retention_days
      noncurrent_expiration_days = 1
    },
    {
      id                         = "tempo"
      prefix                     = "tempo/"
      expiration_days            = var.telemetry_retention_days
      noncurrent_expiration_days = 1
    },
    {
      id                         = "vmbackup"
      prefix                     = "vmbackup/"
      transitions                = [{ days = 7, storage_class = "STANDARD_IA" }]
      expiration_days            = 30
      noncurrent_expiration_days = 1
    },
  ]

  tags = merge(local.tags, { DataClass = "tenant-telemetry" })
}

# ---------------------------------------------------------------- ALB access logs (SSE-S3 is required by ELB)
data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "ELBLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["arn:${local.partition}:s3:::${local.name}-alb-logs-${local.account_id}/alb/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${lookup(local.elb_log_accounts, local.region, "127311923021")}:root"]
    }
  }
}

module "s3_alb_logs" {
  source = "../s3-bucket"

  bucket_name            = "${local.name}-alb-logs-${local.account_id}"
  kms_key_arn            = null
  versioning             = false
  force_destroy          = !var.deletion_protection
  additional_policy_json = data.aws_iam_policy_document.alb_logs.json

  lifecycle_rules = [{
    id                         = "expire"
    expiration_days            = 90
    noncurrent_expiration_days = 1
  }]
  tags = local.tags
}

# ---------------------------------------------------------------- AWS Backup
module "backup_dr_vault" {
  source    = "../backup"
  count     = var.enable_dr_replication ? 1 : 0
  providers = { aws = aws.dr }

  name        = "${local.name}-dr"
  kms_key_arn = module.kms_dr["backup"].key_arn
  create_plan = false
  tags        = local.tags
}

module "backup" {
  source = "../backup"

  name              = local.name
  kms_key_arn       = module.kms["backup"].key_arn
  create_plan       = !local.is_dr
  dr_vault_arn      = var.enable_dr_replication ? module.backup_dr_vault[0].vault_arn : null
  enable_vault_lock = var.environment == "prod"
  tags              = local.tags
}
