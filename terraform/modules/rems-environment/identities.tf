# EKS Pod Identity roles. Services that do not need AWS APIs (frontend, rems-api,
# authorization-service, chat-engine, mcp-server) deliberately get NO role at all.

locals {
  secret_arn_prefix = "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:rems/${var.environment}"
}

# ---------------------------------------------------------------- platform controllers
module "irsa_alb_controller" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-aws-load-balancer-controller"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.system
  service_account          = "aws-load-balancer-controller"
  policy_json              = file("${path.module}/policies/aws-load-balancer-controller.json")
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid       = "ReadRemsSecretsOnly"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:ListSecretVersionIds"]
    resources = ["${local.secret_arn_prefix}/*"]
  }
  statement {
    sid       = "DecryptViaSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = [module.kms["secrets"].key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }
}

module "irsa_external_secrets" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-external-secrets"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.eso
  service_account          = "external-secrets"
  policy_json              = data.aws_iam_policy_document.external_secrets.json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

data "aws_iam_policy_document" "external_dns" {
  count = var.hosted_zone_id == null ? 0 : 1
  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:${local.partition}:route53:::hostedzone/${var.hosted_zone_id}"]
  }
  statement {
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = ["*"]
  }
}

module "irsa_external_dns" {
  source                   = "../pod-identity"
  count                    = var.hosted_zone_id == null ? 0 : 1
  role_name                = "${local.name}-external-dns"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.dns
  service_account          = "external-dns"
  policy_json              = data.aws_iam_policy_document.external_dns[0].json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

# ---------------------------------------------------------------- observability backends (S3 prefixes)
data "aws_iam_policy_document" "telemetry" {
  for_each = { loki = "loki", tempo = "tempo", vmstorage = "vmbackup" }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [module.s3_telemetry.bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.value}/*", each.value]
    }
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.s3_telemetry.bucket_arn}/${each.value}/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [module.kms["s3"].key_arn]
  }
}

module "irsa_telemetry" {
  source                   = "../pod-identity"
  for_each                 = { loki = "loki", tempo = "tempo", vmstorage = "vmstorage" }
  role_name                = "${local.name}-${each.key}"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.obs
  service_account          = each.value
  policy_json              = data.aws_iam_policy_document.telemetry[each.key].json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

data "aws_iam_policy_document" "otel_audit" {
  statement {
    sid       = "ShipAuditLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${module.monitoring.audit_log_group_name}:*"]
  }
}

module "irsa_otel_collector" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-otel-collector"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.obs
  service_account          = "otel-collector"
  policy_json              = data.aws_iam_policy_document.otel_audit.json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

data "aws_iam_policy_document" "alertmanager" {
  statement {
    actions   = ["sns:Publish"]
    resources = [module.monitoring.alerts_topic_arn]
  }
  statement {
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [module.kms["sns"].key_arn]
  }
}

module "irsa_alertmanager" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-alertmanager"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.mon
  service_account          = "alertmanager"
  policy_json              = data.aws_iam_policy_document.alertmanager.json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

# ---------------------------------------------------------------- REMS services that need AWS
data "aws_iam_policy_document" "metadata_rca" {
  statement {
    sid       = "ListTenantPrefixes"
    actions   = ["s3:ListBucket"]
    resources = [module.s3_documents.bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["tenants/*"]
    }
  }
  statement {
    sid       = "TenantDocuments"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectVersion"]
    resources = ["${module.s3_documents.bucket_arn}/tenants/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [module.kms["s3"].key_arn]
  }
}

module "irsa_metadata_rca" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-metadata-rca"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.ai
  service_account          = "metadata-rca"
  policy_json              = data.aws_iam_policy_document.metadata_rca.json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

module "irsa_llm_gateway" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-llm-gateway"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.ai
  service_account          = "llm-gateway"
  policy_json              = module.ai_platform.gateway_policy_json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

data "aws_iam_policy_document" "data_governance" {
  statement {
    sid       = "ReadTenantDbScanCredentials"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["${local.secret_arn_prefix}/tenant-db/*"]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [module.kms["secrets"].key_arn]
  }
}

module "irsa_data_governance" {
  source                   = "../pod-identity"
  role_name                = "${local.name}-data-governance"
  cluster_name             = module.eks.cluster_name
  namespace                = local.ns.app
  service_account          = "data-governance"
  policy_json              = data.aws_iam_policy_document.data_governance.json
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.tags
}

# ---------------------------------------------------------------- AWS FIS (chaos / AZ failure drills)
data "aws_iam_policy_document" "fis_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fis" {
  count              = var.enable_fis ? 1 : 0
  name               = "${local.name}-fis"
  assume_role_policy = data.aws_iam_policy_document.fis_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "fis" {
  for_each = var.enable_fis ? toset([
    "service-role/AWSFaultInjectionSimulatorNetworkAccess",
    "service-role/AWSFaultInjectionSimulatorRDSAccess",
    "service-role/AWSFaultInjectionSimulatorEC2Access",
    "service-role/AWSFaultInjectionSimulatorEKSAccess",
  ]) : toset([])
  role       = aws_iam_role.fis[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

data "aws_iam_policy_document" "fis_extra" {
  statement {
    actions   = ["elasticache:InterruptClusterAzPower", "elasticache:DescribeReplicationGroups", "tag:GetResources"]
    resources = ["*"]
  }
  statement {
    actions   = ["logs:CreateLogDelivery", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_cloudwatch_log_group" "fis" {
  count             = var.enable_fis ? 1 : 0
  name              = "/rems/${var.environment}/fis"
  retention_in_days = 90
  kms_key_id        = module.kms["logs"].key_arn
  tags              = local.tags
}

resource "aws_iam_role_policy" "fis_extra" {
  count  = var.enable_fis ? 1 : 0
  name   = "elasticache-az-power"
  role   = aws_iam_role.fis[0].id
  policy = data.aws_iam_policy_document.fis_extra.json
}
