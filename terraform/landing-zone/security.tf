# ---------------------------------------------------------------- delegated administrators
resource "aws_guardduty_organization_admin_account" "this" {
  admin_account_id = aws_organizations_account.this["security"].id
  depends_on       = [aws_organizations_organization.this]
}

resource "aws_securityhub_organization_admin_account" "this" {
  admin_account_id = aws_organizations_account.this["security"].id
  depends_on       = [aws_organizations_organization.this]
}

resource "aws_inspector2_delegated_admin_account" "this" {
  account_id = aws_organizations_account.this["security"].id
}

resource "aws_organizations_delegated_administrator" "this" {
  for_each          = toset(["access-analyzer.amazonaws.com", "config.amazonaws.com", "backup.amazonaws.com"])
  account_id        = aws_organizations_account.this["security"].id
  service_principal = each.value
}

# ---------------------------------------------------------------- Log Archive bucket (immutable)
data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:aws:s3:::${var.log_archive_bucket_name}"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.log_archive_bucket_name}/cloudtrail/AWSLogs/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
  statement {
    sid       = "FlowLogsDelivery"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.log_archive_bucket_name}/vpc-flow-logs/*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values   = [aws_organizations_organization.this.id]
    }
  }
  statement {
    sid       = "FlowLogsAclCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.log_archive_bucket_name}"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
  }
}

module "kms_log_archive" {
  source      = "../modules/kms"
  providers   = { aws = aws.log_archive }
  alias       = "rems-log-archive"
  description = "Org CloudTrail and VPC flow logs"
  # Org trail and flow logs write from every member account.
  restrict_service_principals_to_account = false
  service_principals = [
    "cloudtrail.amazonaws.com",
    "delivery.logs.amazonaws.com",
  ]
}

module "log_archive_bucket" {
  source      = "../modules/s3-bucket"
  providers   = { aws = aws.log_archive }
  bucket_name = var.log_archive_bucket_name
  kms_key_arn = module.kms_log_archive.key_arn
  object_lock = {
    mode = "COMPLIANCE"
    days = 365
  }
  lifecycle_rules = [{
    id          = "archive"
    transitions = [{ days = 90, storage_class = "GLACIER_IR" }, { days = 365, storage_class = "DEEP_ARCHIVE" }]
    expiration_days = 2555 # 7 years
  }]
  additional_policy_json = data.aws_iam_policy_document.cloudtrail_bucket.json
}

# ---------------------------------------------------------------- Organization CloudTrail
# CloudWatch Logs copy in the management account enables CIS metric-filter alarms.
module "kms_mgmt_logs" {
  source             = "../modules/kms"
  alias              = "rems-org-trail-logs"
  description        = "CloudWatch Logs copy of the organization trail"
  service_principals = ["logs.${var.region}.amazonaws.com"]
}

resource "aws_cloudwatch_log_group" "org_trail" {
  name              = "/rems/org/cloudtrail"
  retention_in_days = 365
  kms_key_id        = module.kms_mgmt_logs.key_arn
}

data "aws_iam_policy_document" "trail_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "org_trail_logs" {
  name               = "rems-org-trail-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.trail_assume.json
}

data "aws_iam_policy_document" "trail_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.org_trail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "org_trail_logs" {
  name   = "cloudwatch-delivery"
  role   = aws_iam_role.org_trail_logs.id
  policy = data.aws_iam_policy_document.trail_logs.json
}

resource "aws_sns_topic" "org_trail" {
  name              = "rems-org-trail-delivery"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_cloudtrail" "org" {
  name                          = "rems-org-trail"
  s3_bucket_name                = module.log_archive_bucket.bucket_id
  s3_key_prefix                 = "cloudtrail"
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = module.kms_log_archive.key_arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.org_trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.org_trail_logs.arn
  sns_topic_name                = aws_sns_topic.org_trail.name

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  # Data events for the REMS document buckets (tenant data access audit).
  advanced_event_selector {
    name = "rems-tenant-documents-data-events"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field       = "resources.ARN"
      starts_with = ["arn:aws:s3:::rems-prod-rag-documents-"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  depends_on = [module.log_archive_bucket]
}

# ---------------------------------------------------------------- Security account baseline
module "kms_security_sns" {
  source             = "../modules/kms"
  providers          = { aws = aws.security }
  alias              = "rems-security-sns"
  description        = "Security findings topic"
  service_principals = ["events.amazonaws.com"]
}

module "security_baseline" {
  source          = "../modules/security-baseline"
  providers       = { aws = aws.security }
  security_emails = var.security_emails
  sns_kms_key_arn = module.kms_security_sns.key_arn

  depends_on = [
    aws_guardduty_organization_admin_account.this,
    aws_securityhub_organization_admin_account.this,
    aws_inspector2_delegated_admin_account.this,
    aws_organizations_delegated_administrator.this,
  ]
}
