terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial configuration: terraform init -backend-config=backend.hcl
  # S3-native state locking (use_lockfile) - no DynamoDB table required.
  backend "s3" {}
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = "REMS"
      Environment = "staging"
      ManagedBy   = "terraform"
      Repository  = "REMS-AWS-Architecture"
    }
  }
}

provider "aws" {
  alias               = "dr"
  region              = var.region # no DR resources in staging
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = "REMS"
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}
