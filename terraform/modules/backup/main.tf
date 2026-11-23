terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

data "aws_partition" "current" {}

resource "aws_backup_vault" "this" {
  name        = var.name
  kms_key_arn = var.kms_key_arn
  tags        = var.tags
}

# Vault Lock: backups cannot be deleted before min retention, even by admins
# (compliance mode becomes immutable after changeable_for_days).
resource "aws_backup_vault_lock_configuration" "this" {
  count               = var.enable_vault_lock ? 1 : 0
  backup_vault_name   = aws_backup_vault.this.name
  min_retention_days  = var.min_retention_days
  max_retention_days  = var.max_retention_days
  changeable_for_days = var.lock_changeable_for_days
}

resource "aws_backup_plan" "this" {
  count = var.create_plan ? 1 : 0
  name  = var.name

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 20 * * ? *)" # 01:30 IST
    start_window      = 60
    completion_window = 360

    lifecycle {
      delete_after = var.daily_retention_days
    }

    dynamic "copy_action" {
      for_each = var.dr_vault_arn == null ? [] : [var.dr_vault_arn]
      content {
        destination_vault_arn = copy_action.value
        lifecycle {
          delete_after = var.daily_retention_days
        }
      }
    }
  }

  rule {
    rule_name         = "monthly"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 21 1 * ? *)"
    lifecycle {
      cold_storage_after = 30
      delete_after       = 365
    }
  }

  tags = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count              = var.create_plan ? 1 : 0
  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.create_plan ? toset([
    "service-role/AWSBackupServiceRolePolicyForBackup",
    "service-role/AWSBackupServiceRolePolicyForRestores",
    "AWSBackupServiceRolePolicyForS3Backup",
    "AWSBackupServiceRolePolicyForS3Restore",
  ]) : toset([])
  role       = aws_iam_role.this[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# Everything tagged backup=rems-critical (Aurora clusters, document buckets) is protected.
resource "aws_backup_selection" "critical" {
  count        = var.create_plan ? 1 : 0
  name         = "rems-critical"
  plan_id      = aws_backup_plan.this[0].id
  iam_role_arn = aws_iam_role.this[0].arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup"
    value = "rems-critical"
  }
}
