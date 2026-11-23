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
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  p       = data.aws_partition.current.partition
  region  = data.aws_region.current.name
  account = data.aws_caller_identity.current.account_id
}

# ------------------------------------------------------------------ node role (instances launched by Karpenter)
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name                 = "${var.cluster_name}-karpenter-node"
  assume_role_policy   = data.aws_iam_policy_document.node_assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.p}:iam::aws:policy/${each.value}"
}

resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
  tags          = var.tags
}

# ------------------------------------------------------------------ interruption handling
resource "aws_sqs_queue" "interruption" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

data "aws_iam_policy_document" "queue" {
  statement {
    sid       = "EventBridgeWrite"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.url
  policy    = data.aws_iam_policy_document.queue.json
}

locals {
  events = {
    health_event = {
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
    }
    spot_interrupt = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    state_change = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each      = local.events
  name          = "${var.cluster_name}-karpenter-${each.key}"
  event_pattern = jsonencode(each.value)
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.events
  rule     = aws_cloudwatch_event_rule.this[each.key].name
  arn      = aws_sqs_queue.interruption.arn
}

# ------------------------------------------------------------------ controller role (EKS Pod Identity)
data "aws_iam_policy_document" "controller_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name                 = "${var.cluster_name}-karpenter-controller"
  assume_role_policy   = data.aws_iam_policy_document.controller_assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

data "aws_iam_policy_document" "controller" {
  statement {
    sid     = "AllowScopedEC2InstanceAccessActions"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "arn:${local.p}:ec2:${local.region}::image/*",
      "arn:${local.p}:ec2:${local.region}::snapshot/*",
      "arn:${local.p}:ec2:${local.region}:*:security-group/*",
      "arn:${local.p}:ec2:${local.region}:*:subnet/*",
      "arn:${local.p}:ec2:${local.region}:*:capacity-reservation/*",
    ]
  }

  statement {
    sid       = "AllowScopedEC2LaunchTemplateAccessActions"
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = ["arn:${local.p}:ec2:${local.region}:*:launch-template/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid     = "AllowScopedEC2InstanceActionsWithTags"
    actions = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    resources = [
      "arn:${local.p}:ec2:${local.region}:*:fleet/*",
      "arn:${local.p}:ec2:${local.region}:*:instance/*",
      "arn:${local.p}:ec2:${local.region}:*:volume/*",
      "arn:${local.p}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.p}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.p}:ec2:${local.region}:*:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid     = "AllowScopedResourceCreationTagging"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:${local.p}:ec2:${local.region}:*:fleet/*",
      "arn:${local.p}:ec2:${local.region}:*:instance/*",
      "arn:${local.p}:ec2:${local.region}:*:volume/*",
      "arn:${local.p}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.p}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.p}:ec2:${local.region}:*:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${local.p}:ec2:${local.region}:*:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }

  statement {
    sid     = "AllowScopedDeletion"
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    resources = [
      "arn:${local.p}:ec2:${local.region}:*:instance/*",
      "arn:${local.p}:ec2:${local.region}:*:launch-template/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }

  statement {
    sid = "AllowRegionalReadActions"
    actions = [
      "ec2:DescribeAvailabilityZones", "ec2:DescribeImages", "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeInstanceTypes", "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups", "ec2:DescribeSpotPriceHistory", "ec2:DescribeSubnets",
      "ec2:DescribeCapacityReservations",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid       = "AllowSSMReadActions"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.p}:ssm:${local.region}::parameter/aws/service/*"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    actions   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    resources = [aws_sqs_queue.interruption.arn]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid = "AllowScopedInstanceProfileActions"
    actions = [
      "iam:CreateInstanceProfile", "iam:TagInstanceProfile", "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
    ]
    resources = ["arn:${local.p}:iam::${local.account}:instance-profile/*"]
  }

  dynamic "statement" {
    for_each = var.ebs_kms_key_arn == null ? [] : [var.ebs_kms_key_arn]
    content {
      sid       = "AllowEncryptedVolumesWithCMK"
      actions   = ["kms:CreateGrant", "kms:Decrypt", "kms:GenerateDataKeyWithoutPlaintext", "kms:DescribeKey", "kms:ReEncrypt*"]
      resources = [statement.value]
    }
  }

  statement {
    sid       = "AllowAPIServerEndpointDiscovery"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.p}:eks:${local.region}:${local.account}:cluster/${var.cluster_name}"]
  }
}

resource "aws_iam_role_policy" "controller" {
  name   = "karpenter-controller"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller.json
}

resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.controller.arn
}
