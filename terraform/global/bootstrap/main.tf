# Per-account bootstrap: Terraform state bucket (+ DR replica) and GitHub OIDC roles.
# Run once per workload account with local state, then migrate:
#   terraform init && terraform apply -var-file=prod.tfvars
#   terraform init -migrate-state -backend-config=...   (optional)

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = { Project = "REMS", Environment = var.environment, ManagedBy = "terraform", Stack = "bootstrap" }
  }
}

provider "aws" {
  alias               = "dr"
  region              = var.dr_region
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = { Project = "REMS", Environment = var.environment, ManagedBy = "terraform", Stack = "bootstrap", Site = "dr" }
  }
}

locals {
  repo   = "${var.github_org}/${var.platform_repo}"
  prefix = "rems-${var.environment}"
}

# ---------------------------------------------------------------- state encryption + bucket
module "kms_state" {
  source                 = "../../modules/kms"
  alias                  = "rems-tfstate"
  description            = "Terraform state encryption"
  key_administrator_arns = var.admin_role_arns
}

module "kms_state_dr" {
  source                 = "../../modules/kms"
  count                  = var.replicate_state ? 1 : 0
  providers              = { aws = aws.dr }
  alias                  = "rems-tfstate"
  description            = "Terraform state encryption (DR replica bucket)"
  key_administrator_arns = var.admin_role_arns
}

module "state_dr" {
  source      = "../../modules/s3-bucket"
  count       = var.replicate_state ? 1 : 0
  providers   = { aws = aws.dr }
  bucket_name = "rems-tfstate-${var.account_id}-${var.dr_region}"
  kms_key_arn = module.kms_state_dr[0].key_arn
}

module "state" {
  source      = "../../modules/s3-bucket"
  bucket_name = "rems-tfstate-${var.account_id}-${var.region}"
  kms_key_arn = module.kms_state.key_arn
  lifecycle_rules = [{
    id                         = "old-versions"
    noncurrent_expiration_days = 90
  }]
  replication = var.replicate_state ? {
    destination_bucket_arn  = module.state_dr[0].bucket_arn
    destination_kms_key_arn = module.kms_state_dr[0].key_arn
    rtc                     = false
  } : null
}

# ---------------------------------------------------------------- permission boundaries
# Workload boundary: attached to every EKS / Pod Identity role (pass its ARN to the env stacks).
resource "aws_iam_policy" "workload_boundary" {
  name        = "rems-workload-boundary"
  description = "Upper bound for all REMS workload roles (no IAM escalation, no data-store admin)"
  policy      = file("${path.module}/../../../security/iam/permission-boundary-workload.json")
}

# Terraform boundary: the apply role can manage infrastructure but cannot touch org guardrails.
resource "aws_iam_policy" "terraform_boundary" {
  name        = "rems-terraform-boundary"
  description = "Upper bound for the GitHub Actions terraform apply role"
  policy      = file("${path.module}/../../../security/iam/permission-boundary-terraform.json")
}

# ---------------------------------------------------------------- GitHub Actions OIDC roles
data "aws_iam_policy_document" "plan_state" {
  # Plan role can read everything (ReadOnlyAccess) and write only the lock file.
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.state.bucket_arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [module.state.bucket_arn]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [module.kms_state.key_arn]
  }
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "DescribeClusters"
    actions   = ["eks:DescribeCluster", "eks:ListClusters"]
    resources = ["*"]
  }
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  roles = {
    "${local.prefix}-github-terraform-plan" = {
      description         = "terraform plan on pull requests (read-only)"
      subjects            = ["repo:${local.repo}:pull_request"]
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      policy_json         = data.aws_iam_policy_document.plan_state.json
    }
    "${local.prefix}-github-terraform-apply" = {
      description              = "terraform apply from main via the ${var.environment} GitHub Environment (approval gated)"
      subjects                 = ["repo:${local.repo}:environment:${var.environment}"]
      managed_policy_arns      = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      permissions_boundary_arn = aws_iam_policy.terraform_boundary.arn
      max_session_seconds      = 7200
    }
    "${local.prefix}-github-deploy" = {
      description = "Post-deploy smoke tests (EKS view access entry only)"
      subjects    = ["repo:${local.repo}:environment:${var.environment}", "repo:${var.github_org}/*:environment:${var.environment}"]
      policy_json = data.aws_iam_policy_document.deploy.json
    }
  }
}

output "state_bucket" {
  description = "Use in backend.hcl."
  value       = module.state.bucket_id
}

output "github_role_arns" {
  description = "Set as GitHub Environment variables AWS_ROLE_PLAN / AWS_ROLE_APPLY / AWS_ROLE_DEPLOY."
  value       = module.github_oidc.role_arns
}

output "workload_permissions_boundary_arn" {
  description = "Pass as permissions_boundary_arn to the environment stacks."
  value       = aws_iam_policy.workload_boundary.arn
}
