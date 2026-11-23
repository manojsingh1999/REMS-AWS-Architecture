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

resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repositories)
  name                 = "${var.namespace}/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, { Service = each.value })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last N commit-SHA images (rollback window)"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["sha-*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.keep_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

# Cross-account pull for workload accounts (dev/staging/prod/DR node roles).
data "aws_iam_policy_document" "pull" {
  count = length(var.pull_account_ids) > 0 ? 1 : 0
  statement {
    sid     = "CrossAccountPull"
    actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    principals {
      type        = "AWS"
      identifiers = [for id in var.pull_account_ids : "arn:${data.aws_partition.current.partition}:iam::${id}:root"]
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  for_each   = length(var.pull_account_ids) > 0 ? aws_ecr_repository.this : {}
  repository = each.value.name
  policy     = data.aws_iam_policy_document.pull[0].json
}

# Amazon Inspector enhanced, continuous scanning of every REMS image.
resource "aws_ecr_registry_scanning_configuration" "this" {
  count     = var.manage_registry_scanning ? 1 : 0
  scan_type = "ENHANCED"
  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "${var.namespace}/*"
      filter_type = "WILDCARD"
    }
  }
}

resource "aws_ecr_replication_configuration" "this" {
  count = length(var.replication_regions) > 0 ? 1 : 0
  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.replication_regions
        content {
          region      = destination.value
          registry_id = var.registry_account_id
        }
      }
      repository_filter {
        filter      = var.namespace
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
