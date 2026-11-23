terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

# GitHub Actions -> AWS without static credentials.
# Each role trusts only specific repo/branch/environment subjects.

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
  tags            = var.tags
}

locals {
  provider_arn = var.create_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_provider_arn
}

data "aws_iam_policy_document" "assume" {
  for_each = var.roles
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value.subjects
    }
  }
}

resource "aws_iam_role" "this" {
  for_each             = var.roles
  name                 = each.key
  description          = each.value.description
  assume_role_policy   = data.aws_iam_policy_document.assume[each.key].json
  max_session_duration = each.value.max_session_seconds
  permissions_boundary = each.value.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy" "inline" {
  for_each = { for k, v in var.roles : k => v if v.policy_json != null }
  name     = "${each.key}-inline"
  role     = aws_iam_role.this[each.key].id
  policy   = each.value.policy_json
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = merge([
    for role, cfg in var.roles : { for arn in cfg.managed_policy_arns : "${role}|${arn}" => { role = role, arn = arn } }
  ]...)
  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.arn
}
