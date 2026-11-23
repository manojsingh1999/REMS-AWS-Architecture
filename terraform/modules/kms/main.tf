terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_root = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
}

data "aws_iam_policy_document" "this" {
  # Account root retains control so the key can never become unmanageable.
  statement {
    sid       = "EnableRootAccountPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  dynamic "statement" {
    for_each = length(var.key_administrator_arns) > 0 ? [1] : []
    content {
      sid = "KeyAdministrators"
      actions = [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
        "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
        "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
        "kms:ReplicateKey"
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.key_administrator_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.service_principals) > 0 ? [1] : []
    content {
      sid       = "AllowAwsServicesUse"
      actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"]
      resources = ["*"]
      principals {
        type        = "Service"
        identifiers = var.service_principals
      }
      dynamic "condition" {
        for_each = var.restrict_service_principals_to_account ? [1] : []
        content {
          test     = "StringEquals"
          variable = "aws:SourceAccount"
          values   = [data.aws_caller_identity.current.account_id]
        }
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.key_user_arns) > 0 ? [1] : []
    content {
      sid       = "KeyUsers"
      actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.key_user_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = var.primary_key_arn == null ? 1 : 0

  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  rotation_period_in_days = 365
  multi_region            = var.multi_region
  policy                  = data.aws_iam_policy_document.this.json
  tags                    = merge(var.tags, { Name = var.alias })
}

# Replica of a multi-Region key (used for DR region resources).
resource "aws_kms_replica_key" "this" {
  count = var.primary_key_arn != null ? 1 : 0

  description             = "${var.description} (replica)"
  primary_key_arn         = var.primary_key_arn
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.this.json
  tags                    = merge(var.tags, { Name = var.alias })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = var.primary_key_arn == null ? aws_kms_key.this[0].key_id : aws_kms_replica_key.this[0].key_id
}
