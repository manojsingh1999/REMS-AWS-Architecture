terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

# Runs in the Security (delegated admin) account, once per region.
# The management account delegates administration in terraform/landing-zone.

data "aws_region" "current" {}
data "aws_partition" "current" {}

# ------------------------------------------------------------------ GuardDuty
resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  tags                         = var.tags
}

resource "aws_guardduty_organization_configuration" "this" {
  detector_id                      = aws_guardduty_detector.this.id
  auto_enable_organization_members = "ALL"
}

resource "aws_guardduty_organization_configuration_feature" "this" {
  for_each    = toset(["S3_DATA_EVENTS", "EKS_AUDIT_LOGS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "LAMBDA_NETWORK_LOGS"])
  detector_id = aws_guardduty_detector.this.id
  name        = each.value
  auto_enable = "ALL"
}

resource "aws_guardduty_organization_configuration_feature" "runtime" {
  detector_id = aws_guardduty_detector.this.id
  name        = "RUNTIME_MONITORING"
  auto_enable = "ALL"

  additional_configuration {
    name        = "EKS_ADDON_MANAGEMENT"
    auto_enable = "ALL"
  }
}

# ------------------------------------------------------------------ Security Hub
resource "aws_securityhub_account" "this" {
  enable_default_standards  = false
  auto_enable_controls      = true
  control_finding_generator = "SECURITY_CONTROL"
}

resource "aws_securityhub_organization_configuration" "this" {
  auto_enable           = true
  auto_enable_standards = "DEFAULT"
  depends_on            = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/3.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_securityhub_finding_aggregator" "this" {
  count        = var.is_aggregation_region ? 1 : 0
  linking_mode = "ALL_REGIONS"
  depends_on   = [aws_securityhub_account.this]
}

# ------------------------------------------------------------------ Inspector (ECR + EC2)
resource "aws_inspector2_organization_configuration" "this" {
  auto_enable {
    ec2         = true
    ecr         = true
    lambda      = false
    lambda_code = false
  }
}

# ------------------------------------------------------------------ IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "org" {
  analyzer_name = "rems-org-analyzer"
  type          = "ORGANIZATION"
  tags          = var.tags
}

# ------------------------------------------------------------------ AWS Config aggregator
data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config_aggregator" {
  count              = var.is_aggregation_region ? 1 : 0
  name               = "rems-config-aggregator"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  count      = var.is_aggregation_region ? 1 : 0
  role       = aws_iam_role.config_aggregator[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "org" {
  count = var.is_aggregation_region ? 1 : 0
  name  = "rems-org"
  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator[0].arn
  }
  tags = var.tags
}

# ------------------------------------------------------------------ high-severity findings -> SNS
resource "aws_sns_topic" "security" {
  name              = "rems-security-findings"
  kms_master_key_id = var.sns_kms_key_arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "security_email" {
  for_each  = toset(var.security_emails)
  topic_arn = aws_sns_topic.security.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_event_rule" "high_findings" {
  name        = "rems-high-severity-findings"
  description = "GuardDuty and Security Hub HIGH/CRITICAL findings"
  event_pattern = jsonencode({
    source      = ["aws.guardduty", "aws.securityhub"]
    detail-type = ["GuardDuty Finding", "Security Hub Findings - Imported"]
    "$or" = [
      { detail = { severity = [{ numeric = [">=", 7] }] } },
      { detail = { findings = { Severity = { Label = ["HIGH", "CRITICAL"] } } } }
    ]
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "high_findings" {
  rule = aws_cloudwatch_event_rule.high_findings.name
  arn  = aws_sns_topic.security.arn
}

data "aws_iam_policy_document" "security_topic" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "security" {
  arn    = aws_sns_topic.security.arn
  policy = data.aws_iam_policy_document.security_topic.json
}
