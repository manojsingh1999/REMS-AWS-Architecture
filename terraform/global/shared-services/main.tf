# Shared Services account: central ECR for all REMS images + GitHub OIDC push role.

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
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = { Project = "REMS", Environment = "shared", ManagedBy = "terraform" }
  }
}

locals {
  services = [
    "rems-frontend",
    "rems-api",
    "authorization-service",
    "data-governance",
    "metadata-rca",
    "chat-engine",
    "mcp-server",
  ]
  workload_account_ids = values(var.workload_account_ids)
}

module "kms_ecr" {
  source                 = "../../modules/kms"
  alias                  = "rems-ecr"
  description            = "REMS container images"
  key_administrator_arns = var.admin_role_arns
  # Node roles in workload accounts decrypt image layers during pull.
  key_user_arns = [for id in local.workload_account_ids : "arn:aws:iam::${id}:root"]
}

module "ecr" {
  source              = "../../modules/ecr"
  namespace           = "rems"
  repositories        = local.services
  kms_key_arn         = module.kms_ecr.key_arn
  pull_account_ids    = local.workload_account_ids
  replication_regions = [var.dr_region]
  registry_account_id = var.account_id
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "Auth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "PushRemsRepos"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
      "ecr:DescribeImageScanFindings",
    ]
    resources = values(module.ecr.repository_arns)
  }
  statement {
    sid       = "EncryptLayers"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt", "kms:Encrypt"]
    resources = [module.kms_ecr.key_arn]
  }
}

module "github_oidc" {
  source = "../../modules/github-oidc"
  roles = {
    "rems-github-ecr-push" = {
      description = "Build pipelines of REMS service repos push images (main branch and release tags only)"
      subjects = flatten([
        for svc in local.services : [
          "repo:${var.github_org}/${svc}:ref:refs/heads/main",
          "repo:${var.github_org}/${svc}:ref:refs/tags/v*",
        ]
      ])
      policy_json = data.aws_iam_policy_document.ecr_push.json
    }
  }
}

output "repository_urls" {
  description = "ECR repositories (use in Helm image.repository)."
  value       = module.ecr.repository_urls
}

output "ecr_push_role_arn" {
  description = "Set as AWS_ECR_PUSH_ROLE variable in service repos."
  value       = module.github_oidc.role_arns["rems-github-ecr-push"]
}
