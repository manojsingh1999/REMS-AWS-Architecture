# Multi-account landing zone (run from the Management account by the platform team).
# If AWS Control Tower already governs the org, import the OUs/accounts and keep the SCPs.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "REMS", Stack = "landing-zone", ManagedBy = "terraform" }
  }
}

# Delegated security administrator account.
provider "aws" {
  alias  = "security"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.this["security"].id}:role/OrganizationAccountAccessRole"
  }
  default_tags {
    tags = { Project = "REMS", Stack = "landing-zone", ManagedBy = "terraform" }
  }
}

# Log Archive account.
provider "aws" {
  alias  = "log_archive"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.this["log-archive"].id}:role/OrganizationAccountAccessRole"
  }
  default_tags {
    tags = { Project = "REMS", Stack = "landing-zone", ManagedBy = "terraform" }
  }
}

# ---------------------------------------------------------------- organization
resource "aws_organizations_organization" "this" {
  feature_set = "ALL"
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "guardduty.amazonaws.com",
    "malware-protection.guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "inspector2.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "sso.amazonaws.com",
    "backup.amazonaws.com",
    "ram.amazonaws.com",
    "fms.amazonaws.com",
  ]
  enabled_policy_types = ["SERVICE_CONTROL_POLICY", "TAG_POLICY", "BACKUP_POLICY"]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  root_id = aws_organizations_organization.this.roots[0].id

  top_ous = ["Security", "Infrastructure", "Workloads", "Sandbox", "Suspended"]

  accounts = {
    "security"        = { ou = "Security", email = "aws+rems-security@${var.email_domain}" }
    "log-archive"     = { ou = "Security", email = "aws+rems-log-archive@${var.email_domain}" }
    "network"         = { ou = "Infrastructure", email = "aws+rems-network@${var.email_domain}" }
    "shared-services" = { ou = "Infrastructure", email = "aws+rems-shared@${var.email_domain}" }
    "rems-dev"        = { ou = "NonProd", email = "aws+rems-dev@${var.email_domain}" }
    "rems-staging"    = { ou = "NonProd", email = "aws+rems-staging@${var.email_domain}" }
    "rems-prod"       = { ou = "Prod", email = "aws+rems-prod@${var.email_domain}" }
  }

  ou_ids = merge(
    { for k, ou in aws_organizations_organizational_unit.top : k => ou.id },
    { for k, ou in aws_organizations_organizational_unit.workloads : k => ou.id },
  )
}

resource "aws_organizations_organizational_unit" "top" {
  for_each  = toset(local.top_ous)
  name      = each.value
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "workloads" {
  for_each  = toset(["NonProd", "Prod"])
  name      = each.value
  parent_id = aws_organizations_organizational_unit.top["Workloads"].id
}

resource "aws_organizations_account" "this" {
  for_each                   = local.accounts
  name                       = each.key
  email                      = each.value.email
  parent_id                  = local.ou_ids[each.value.ou]
  role_name                  = "OrganizationAccountAccessRole"
  iam_user_access_to_billing = "DENY"
  close_on_deletion          = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name, iam_user_access_to_billing]
  }
}
